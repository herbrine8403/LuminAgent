#import "LAWebTools.h"

// 错误域定义。
NSString * const LAWebToolsErrorDomain = @"org.luminagent.webtools";

@implementation LACancellationToken
- (void)cancel { self.cancelled = YES; }
@end

@implementation LAWebFetchResult
@end

@implementation LAWebSearchItem
@end

@implementation LAWebTools

- (instancetype)init {
    if (self = [super init]) {
        _defaultTimeoutSeconds = 30;
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.waitsForConnectivity = NO;
        _session = [NSURLSession sessionWithConfiguration:cfg];
    }
    return self;
}

#pragma mark - 内部：同步等待封装（超时+取消）

// 通用同步 GET：data/response/error 三回填；token 取消时主动 cancel task。
- (BOOL)syncGET:(NSURL *)url
        timeout:(NSTimeInterval)timeout
          token:(nullable LACancellationToken *)token
           data:(NSData * _Nullable * _Nullable)outData
       response:(NSHTTPURLResponse * _Nullable * _Nullable)outResp
          error:(NSError **)error {
    NSTimeInterval t = timeout > 0 ? timeout : self.defaultTimeoutSeconds;
    if (t <= 0) { t = 30; }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:t];
    [req setValue:@"LuminAgent/1.0 (iOS; webfetch)" forHTTPHeaderField:@"User-Agent"];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSData *data = nil;
    __block NSURLResponse *resp = nil;
    __block NSError *taskErr = nil;
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req
                                                completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        data = d; resp = r; taskErr = e;
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    // 轮询等待：兼顾取消（iOS 无 NSOperation 依赖，token 即取消源）。
    int64_t sliceMs = 100;
    NSTimeInterval waited = 0;
    while (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, sliceMs * NSEC_PER_MSEC)) != 0) {
        if (token && token.isCancelled) {
            [task cancel];
            if (error) { *error = [NSError errorWithDomain:LAWebToolsErrorDomain code:LAWebToolsErrorCancelled userInfo:@{NSLocalizedDescriptionKey: @"请求已取消。"}]; }
            return NO;
        }
        waited += sliceMs / 1000.0;
        if (waited >= t + 2) { // 兜底：NSURLSession 超时未回则主动取消
            [task cancel];
            if (error) { *error = [NSError errorWithDomain:LAWebToolsErrorDomain code:LAWebToolsErrorTimeout userInfo:@{NSLocalizedDescriptionKey: @"请求超时。"}]; }
            return NO;
        }
    }
    if (taskErr) {
        if (error) {
            NSInteger code = (taskErr.code == NSURLErrorTimedOut) ? LAWebToolsErrorTimeout
                           : (taskErr.code == NSURLErrorCancelled ? LAWebToolsErrorCancelled : LAWebToolsErrorHTTPError);
            *error = [NSError errorWithDomain:LAWebToolsErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: taskErr.localizedDescription ?: @"网络请求失败。", NSUnderlyingErrorKey: taskErr}];
        }
        return NO;
    }
    if (outData) { *outData = data; }
    if (outResp) { *outResp = [resp isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)resp : nil; }
    return YES;
}

// ATS 门禁：默认仅 https；http 需调用方显式 allowInsecure=YES。
- (BOOL)gateATS:(NSURL *)url allowInsecure:(BOOL)allowInsecure error:(NSError **)error {
    NSString *scheme = [[url scheme] lowercaseString];
    if ([scheme isEqualToString:@"https"]) { return YES; }
    if ([scheme isEqualToString:@"http"] && allowInsecure) { return YES; }
    if (error) { *error = [NSError errorWithDomain:LAWebToolsErrorDomain code:LAWebToolsErrorInsecureDenied userInfo:@{NSLocalizedDescriptionKey: @"ATS 默认仅允许 HTTPS，明文 HTTP 需显式确认（allowInsecure=YES）。"}]; }
    return NO;
}

#pragma mark - HTML→markdown/text 轻量提取

// 实体解码（覆盖常见五种 + 数字实体）。
- (NSString *)decodeEntities:(NSString *)s {
    NSDictionary *map = @{@"&amp;": @"&", @"&lt;": @"<", @"&gt;": @">", @"&quot;": @"\"", @"&#39;": @"'", @"&nbsp;": @" "};
    NSMutableString *m = [s mutableCopy];
    for (NSString *k in map) { [m replaceOccurrencesOfString:k withString:map[k] options:0 range:NSMakeRange(0, m.length)]; }
    return [m copy];
}

- (NSString *)extractTitle:(NSString *)html {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"<title[^>]*>(.*?)</title>" options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
    if (!m || m.numberOfRanges < 2) { return nil; }
    return [[self decodeEntities:[html substringWithRange:[m rangeAtIndex:1]]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// 轻量 HTML→markdown：保留标题/链接/换行，去 script/style， strip 其余标签。
- (NSString *)htmlToMarkdown:(NSString *)html {
    NSMutableString *m = [html mutableCopy];
    // 去 script/style 块。
    for (NSString *pat in @[@"<script[^>]*>.*?</script>", @"<style[^>]*>.*?</style>"]) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pat options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators error:nil];
        [re replaceMatchesInString:m options:0 range:NSMakeRange(0, m.length) withTemplate:@""];
    }
    // 标题 h1-h3 → markdown #。
    NSArray *heads = @[@"h1", @"h2", @"h3"];
    for (NSString *h in heads) {
        NSString *pat = [NSString stringWithFormat:@"<%@[^>]*>(.*?)</%@>", h, h];
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pat options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators error:nil];
        NSString *prefix = [h isEqualToString:@"h1"] ? @"\n# " : ([h isEqualToString:@"h2"] ? @"\n## " : @"\n### ");
        // 用 $1 需转义：先逐个替换。
        NSArray<NSTextCheckingResult *> *ms = [[re matchesInString:m options:0 range:NSMakeRange(0, m.length)] reverseObjectEnumerator].allObjects;
        for (NSTextCheckingResult *r in ms) {
            NSString *inner = [m substringWithRange:[r rangeAtIndex:1]];
            [m replaceCharactersInRange:r.range withString:[prefix stringByAppendingString:inner]];
        }
    }
    // 链接 <a href>inner</a> → [inner](href)。
    {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"<a[^>]*href\\s*=\\s*\"([^\"]*)\"[^>]*>(.*?)</a>" options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators error:nil];
        NSArray<NSTextCheckingResult *> *ms = [[re matchesInString:m options:0 range:NSMakeRange(0, m.length)] reverseObjectEnumerator].allObjects;
        for (NSTextCheckingResult *r in ms) {
            NSString *href = [m substringWithRange:[r rangeAtIndex:1]];
            NSString *inner = [m substringWithRange:[r rangeAtIndex:2]];
            NSRegularExpression *tagStrip = [NSRegularExpression regularExpressionWithPattern:@"<[^>]+>" options:0 error:nil];
            inner = [tagStrip stringByReplacingMatchesInString:inner options:0 range:NSMakeRange(0, inner.length) withTemplate:@""];
            [m replaceCharactersInRange:r.range withString:[NSString stringWithFormat:@"[%@](%@)", inner, href]];
        }
    }
    // 块标签 → 换行。
    {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"<(p|br|div|li|tr|h[1-6])[^>]*>" options:NSRegularExpressionCaseInsensitive error:nil];
        [re replaceMatchesInString:m options:0 range:NSMakeRange(0, m.length) withTemplate:@"\n"];
    }
    // 去剩余标签。
    {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"<[^>]+>" options:0 error:nil];
        [re replaceMatchesInString:m options:0 range:NSMakeRange(0, m.length) withTemplate:@""];
    }
    NSString *decoded = [self decodeEntities:m];
    // 压缩 3+ 换行为双换行。
    NSRegularExpression *nls = [NSRegularExpression regularExpressionWithPattern:@"\n{3,}" options:0 error:nil];
    decoded = [nls stringByReplacingMatchesInString:[decoded mutableCopy] options:0 range:NSMakeRange(0, decoded.length) withTemplate:@"\n\n"];
    return [decoded stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)htmlToText:(NSString *)html {
    NSString *md = [self htmlToMarkdown:html];
    // 纯文本：再去掉 markdown 链接括号，保留可读性。
    NSRegularExpression *link = [NSRegularExpression regularExpressionWithPattern:@"\\[([^\\]]*)\\]\\([^\\)]*\\)" options:0 error:nil];
    NSMutableString *m = [md mutableCopy];
    [link replaceMatchesInString:m options:0 range:NSMakeRange(0, m.length) withTemplate:@"$1"];
    return [m copy];
}

#pragma mark - webfetch / websearch

- (nullable LAWebFetchResult *)webfetchURLString:(NSString *)urlString format:(LAWebFetchFormat)format allowInsecure:(BOOL)allowInsecure timeout:(NSTimeInterval)timeout cancellationToken:(nullable LACancellationToken *)token error:(NSError **)error {
    if (!urlString || urlString.length == 0) {
        if (error) { *error = [NSError errorWithDomain:LAWebToolsErrorDomain code:LAWebToolsErrorInvalidArgument userInfo:@{NSLocalizedDescriptionKey: @"URL 为空。"}]; }
        return nil;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url || !url.scheme) {
        if (error) { *error = [NSError errorWithDomain:LAWebToolsErrorDomain code:LAWebToolsErrorInvalidURL userInfo:@{NSLocalizedDescriptionKey: @"URL 非法。"}]; }
        return nil;
    }
    if (![self gateATS:url allowInsecure:allowInsecure error:error]) { return nil; }
    if (token && token.isCancelled) {
        if (error) { *error = [NSError errorWithDomain:LAWebToolsErrorDomain code:LAWebToolsErrorCancelled userInfo:@{NSLocalizedDescriptionKey: @"请求已取消。"}]; }
        return nil;
    }
    NSData *data = nil;
    NSHTTPURLResponse *resp = nil;
    if (![self syncGET:url timeout:timeout token:token data:&data response:&resp error:error]) { return nil; }
    if (resp && (resp.statusCode < 200 || resp.statusCode >= 300)) {
        if (error) { *error = [NSError errorWithDomain:LAWebToolsErrorDomain code:LAWebToolsErrorHTTPError userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld。", (long)resp.statusCode]}]; }
        return nil;
    }
    NSString *mime = resp.MIMEType;
    NSStringEncoding enc = NSUTF8StringEncoding;
    NSString *raw = [[NSString alloc] initWithData:data ?: [NSData data] encoding:enc];
    if (!raw) { raw = [[NSString alloc] initWithData:data ?: [NSData data] encoding:NSISOLatin1StringEncoding] ?: @""; }
    LAWebFetchResult *r = [[LAWebFetchResult alloc] init];
    r.sourceURL = resp.URL.absoluteString ?: urlString; // 跟随重定向后的实际 URL
    r.mimeType = mime;
    r.format = format;
    BOOL isHTML = (!mime) || ([mime rangeOfString:@"html"].location != NSNotFound);
    if (isHTML) {
        r.title = [self extractTitle:raw];
        r.content = (format == LAWebFetchFormatMarkdown) ? [self htmlToMarkdown:raw] : [self htmlToText:raw];
    } else {
        r.content = raw; // 文本类 MIME 直接返回正文
    }
    return r;
}

- (nullable NSArray<LAWebSearchItem *> *)websearchQuery:(NSString *)query maxResults:(NSInteger)maxResults timeout:(NSTimeInterval)timeout cancellationToken:(nullable LACancellationToken *)token error:(NSError **)error {
    if (!query || query.length == 0) {
        if (error) { *error = [NSError errorWithDomain:LAWebToolsErrorDomain code:LAWebToolsErrorInvalidArgument userInfo:@{NSLocalizedDescriptionKey: @"搜索 query 为空。"}]; }
        return nil;
    }
    if (!self.searchEndpoint || self.searchEndpoint.length == 0) {
        if (error) { *error = [NSError errorWithDomain:LAWebToolsErrorDomain code:LAWebToolsErrorInvalidArgument userInfo:@{NSLocalizedDescriptionKey: @"未配置搜索网关（searchEndpoint 为空）。请在设置中配置搜索 API 后重试；本机不内置抓取搜索引擎。"}]; }
        return nil;
    }
    NSURLComponents *parts = [NSURLComponents componentsWithString:self.searchEndpoint];
    if (!parts) {
        if (error) { *error = [NSError errorWithDomain:LAWebToolsErrorDomain code:LAWebToolsErrorInvalidURL userInfo:@{NSLocalizedDescriptionKey: @"搜索网关地址非法。"}]; }
        return nil;
    }
    NSMutableArray<NSURLQueryItem *> *items = parts.queryItems ? [parts.queryItems mutableCopy] : [NSMutableArray array];
    [items addObject:[NSURLQueryItem queryItemWithName:@"q" value:query]];
    [items addObject:[NSURLQueryItem queryItemWithName:@"n" value:[NSString stringWithFormat:@"%ld", (long)(maxResults > 0 ? maxResults : 8)]]];
    parts.queryItems = items;
    NSURL *url = parts.URL;
    if (!url) {
        if (error) { *error = [NSError errorWithDomain:LAWebToolsErrorDomain code:LAWebToolsErrorInvalidURL userInfo:@{NSLocalizedDescriptionKey: @"搜索 URL 组装失败。"}]; }
        return nil;
    }
    // 搜索网关同样遵守 ATS（默认 HTTPS）。
    if (![self gateATS:url allowInsecure:NO error:error]) { return nil; }
    NSData *data = nil;
    NSHTTPURLResponse *resp = nil;
    if (![self syncGET:url timeout:timeout token:token data:&data response:&resp error:error]) { return nil; }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
        if (error) { *error = [NSError errorWithDomain:LAWebToolsErrorDomain code:LAWebToolsErrorHTTPError userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"搜索网关 HTTP %ld。", (long)resp.statusCode]}]; }
        return nil;
    }
    // 期望网关返回 JSON 数组 [{title,snippet,url}]；兼容 results 包裹。
    NSError *jErr = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:&jErr];
    if (!obj) { if (error) { *error = jErr; } return nil; }
    NSArray *arr = nil;
    if ([obj isKindOfClass:[NSArray class]]) { arr = obj; }
    else if ([obj isKindOfClass:[NSDictionary class]]) {
        id inner = obj[@"results"] ?: obj[@"items"];
        if ([inner isKindOfClass:[NSArray class]]) { arr = inner; }
    }
    if (!arr) {
        if (error) { *error = [NSError errorWithDomain:LAWebToolsErrorDomain code:LAWebToolsErrorHTTPError userInfo:@{NSLocalizedDescriptionKey: @"搜索网关返回格式无法解析（期望 [{title,snippet,url}]）。"}]; }
        return nil;
    }
    NSMutableArray<LAWebSearchItem *> *out = [NSMutableArray array];
    for (id e in arr) {
        if (![e isKindOfClass:[NSDictionary class]]) { continue; }
        LAWebSearchItem *it = [[LAWebSearchItem alloc] init];
        it.title = [NSString stringWithFormat:@"%@", e[@"title"] ?: @""];
        it.snippet = [NSString stringWithFormat:@"%@", e[@"snippet"] ?: e[@"description"] ?: @""];
        it.sourceURL = [NSString stringWithFormat:@"%@", e[@"url"] ?: e[@"link"] ?: @""];
        if (it.sourceURL.length == 0) { continue; } // 无来源链接的结果丢弃（spec 要求附来源）
        [out addObject:it];
        if (maxResults > 0 && out.count >= (NSUInteger)maxResults) { break; }
    }
    return [out copy];
}

@end
