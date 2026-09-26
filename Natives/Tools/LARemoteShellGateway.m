#import "LARemoteShellGateway.h"

// 错误域定义。
NSString * const LARemoteShellErrorDomain = @"org.luminagent.remoteshell";

@implementation LARemoteGatewayConfig

+ (instancetype)sshConfigWithHost:(NSString *)host port:(NSInteger)port username:(NSString *)user keyReference:(NSString *)keyRef {
    LARemoteGatewayConfig *c = [[self alloc] init];
    c.channel = LARemoteChannelSSH;
    c.host = host;
    c.port = port > 0 ? port : 22;
    c.username = user;
    c.keyReference = keyRef;
    c.timeoutSeconds = 30;
    return c;
}

+ (instancetype)containerConfigWithEndpointURL:(NSString *)url {
    LARemoteGatewayConfig *c = [[self alloc] init];
    c.channel = LARemoteChannelContainer;
    c.endpointURL = url;
    c.timeoutSeconds = 60;
    return c;
}

+ (instancetype)appIntentConfig {
    LARemoteGatewayConfig *c = [[self alloc] init];
    c.channel = LARemoteChannelAppIntent;
    c.timeoutSeconds = 30;
    return c;
}

- (id)copyWithZone:(NSZone *)zone {
    LARemoteGatewayConfig *c = [[[self class] allocWithZone:zone] init];
    c.channel = self.channel;
    c.host = [self.host copy];
    c.port = self.port;
    c.username = [self.username copy];
    c.keyReference = [self.keyReference copy];
    c.endpointURL = [self.endpointURL copy];
    c.timeoutSeconds = self.timeoutSeconds;
    return c;
}

@end

@implementation LARemoteShellRequest
+ (instancetype)requestWithCommand:(NSString *)command workdir:(nullable NSString *)workdir {
    LARemoteShellRequest *r = [[self alloc] init];
    r.command = command ?: @"";
    r.workdir = workdir;
    r.timeoutSeconds = 0;
    return r;
}
@end

@implementation LARemoteShellResult
@end

@implementation LARemoteShellGateway

#pragma mark - 危险命令表（内置，默认 deny）

// 危险表：rm -rf 根、格式化、fork 炸弹、curl|sh 管道、块设备直写等。
// 命中即拒绝，不再走权限卡（spec：SHALL 默认 deny）。
+ (NSArray<NSString *> *)dangerousPatterns {
    return @[
        @"rm -rf /",            // 删除根（含变体由正则兜底）
        @"mkfs",                // 格式化文件系统
        @":(){:|:&}",           // fork 炸弹（含空格变体由归一化兜底）
        @"curl|sh",             // 投毒管道（curl/wget 管道进 shell）
        @"wget|sh",
        @"dd of=/dev",          // 块设备直写
        @"chmod -R 777 /",      // 根权限破坏
        @"> /dev/sd",           // 裸盘写入
        @"shutdown",            // 关机/重启类
        @"reboot",
        @"halt"
    ];
}

// 归一化：去多余空白，便于变体匹配。
+ (NSString *)normalizedCommand:(NSString *)cmd {
    NSString *s = [cmd stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSRegularExpression *ws = [NSRegularExpression regularExpressionWithPattern:@"[\\s]+" options:0 error:nil];
    s = [ws stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@" "];
    return s;
}

+ (BOOL)isDangerousCommand:(NSString *)command reason:(NSString * _Nullable * _Nullable)reason {
    if (!command || command.length == 0) { return NO; }
    NSString *n = [self normalizedCommand:command];
    NSString *lower = [n lowercaseString];
    // 逐项子串匹配（大小写不敏感）。
    for (NSString *pat in [self dangerousPatterns]) {
        NSString *pl = [pat lowercaseString];
        if ([pl isEqualToString:@"curl|sh"] || [pl isEqualToString:@"wget|sh"]) {
            // 管道投毒：curl/wget … | (sh|bash|zsh)。
            BOOL hasDL = ([lower rangeOfString:@"curl"].location != NSNotFound) || ([lower rangeOfString:@"wget"].location != NSNotFound);
            NSRegularExpression *pipe = [NSRegularExpression regularExpressionWithPattern:@"\\|\\s*(sh|bash|zsh|dash)(\\s|$|;)" options:0 error:nil];
            if (hasDL && [pipe firstMatchInString:lower options:0 range:NSMakeRange(0, lower.length)]) {
                if (reason) { *reason = @"检测到“下载管道进 shell”（curl/wget | sh），存在投毒风险，已默认拒绝。"; }
                return YES;
            }
            continue;
        }
        if ([pl isEqualToString:@":(){:|:&}"]) {
            NSString *compact = [[lower componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] componentsJoinedByString:@""];
            if ([compact rangeOfString:@":(){:|:&}"].location != NSNotFound || [compact rangeOfString:@":(){:¦:&}"].location != NSNotFound) {
                if (reason) { *reason = @"检测到 fork 炸弹特征，已默认拒绝。"; }
                return YES;
            }
            continue;
        }
        if ([lower rangeOfString:pl].location != NSNotFound) {
            if (reason) { *reason = [NSString stringWithFormat:@"命中危险命令表“%@”，已默认拒绝。", pat]; }
            return YES;
        }
    }
    // rm 变体兜底：rm … -rf … / 或 rm … --no-preserve-root。
    {
        NSRegularExpression *rmRoot = [NSRegularExpression regularExpressionWithPattern:@"(^|[;&|])\\s*rm\\s+.*-\\w*r\\w*f.*\\s/\\s*(\\s|$|[;&])" options:0 error:nil];
        NSRegularExpression *noPreserve = [NSRegularExpression regularExpressionWithPattern:@"rm\\s+.*--no-preserve-root" options:0 error:nil];
        if ([rmRoot firstMatchInString:lower options:0 range:NSMakeRange(0, lower.length)] ||
            [noPreserve firstMatchInString:lower options:0 range:NSMakeRange(0, lower.length)]) {
            if (reason) { *reason = @"检测到 rm -rf 根目录变体，已默认拒绝。"; }
            return YES;
        }
    }
    return NO;
}

#pragma mark - 主入口

// 本机任意 bash 直接拒绝并返回配置指引（红线：本类永不调用 NSTask/system/posix_spawn）。
- (nullable LARemoteShellResult *)executeRequest:(LARemoteShellRequest *)request error:(NSError **)error {
    if (!request || request.command.length == 0) {
        if (error) { *error = [NSError errorWithDomain:LARemoteShellErrorDomain code:LARemoteShellErrorInvalidArgument userInfo:@{NSLocalizedDescriptionKey: @"命令为空。"}]; }
        return nil;
    }
    // 1）危险命令：默认 deny，不弹权限卡。
    NSString *reason = nil;
    if ([[self class] isDangerousCommand:request.command reason:&reason]) {
        if (error) {
            *error = [NSError errorWithDomain:LARemoteShellErrorDomain
                                         code:LARemoteShellErrorDangerousDenied
                                     userInfo:@{NSLocalizedDescriptionKey: reason ?: @"危险命令，已默认拒绝。"}];
        }
        return nil;
    }
    // 2）非危险命令同样先走权限 ask（spec：危险弹卡、拒绝返回取消事件；此处推广到所有 shell）。
    if (self.permissionCenter) {
        LAPermissionRequest *req = [LAPermissionRequest requestWithTool:@"shell"
                                                                target:request.command
                                                                reason:@"shell 需求需确认执行通道（本机永不执行）。"];
        LAPermissionDecision d = [self.permissionCenter askPermission:req];
        if (d != LAPermissionDecisionAllow) {
            if (error) { *error = [NSError errorWithDomain:LARemoteShellErrorDomain code:LARemoteShellErrorPermissionDenied userInfo:@{NSLocalizedDescriptionKey: @"用户拒绝了 shell 执行请求，已取消。"}]; }
            return nil;
        }
    }
    LARemoteGatewayConfig *cfg = self.config;
    LARemoteChannel channel = cfg ? cfg.channel : LARemoteChannelLocalDenied;
    // 3）本机通道：直接拒绝 + 配置指引（spec Scenario：提示配置远端网关或改用文件工具）。
    if (channel == LARemoteChannelLocalDenied || !cfg) {
        if (error) {
            NSString *msg = @"非越狱 iOS 不支持本机任意 bash，已拒绝执行。请：①在设置中配置远端执行网关（自备 SSH/容器）；②或改用文件工具（read/write/edit）完成操作；③或经 App Intent/快捷指令通道下发。";
            *error = [NSError errorWithDomain:LARemoteShellErrorDomain
                                         code:LARemoteShellErrorLocalDenied
                                     userInfo:@{NSLocalizedDescriptionKey: msg}];
        }
        return nil;
    }
    // 4）Minimal 声明：仅记录，不执行。
    if (channel == LARemoteChannelMinimalNote) {
        LARemoteShellResult *r = [[LARemoteShellResult alloc] init];
        r.executed = NO;
        r.channel = channel;
        r.userGuidance = @"Minimal 模式声明：该命令仅记录执行意图，不实际执行。";
        return r;
    }
    // 5）远端/App Intent 通道：需 handoff 投递器；未配置则返回 NotConfigured 指引。
    if (!self.handoff) {
        if (error) {
            NSString *msg = (channel == LARemoteChannelAppIntent)
                ? @"App Intent/快捷指令通道尚未绑定投递器，请先在宿主 App 实现 LARemoteHandoff 后重试。"
                : @"远端网关已选型但未就绪：请补全主机/端口/凭证（Keychain 引用）或容器 endpoint 后重试。";
            *error = [NSError errorWithDomain:LARemoteShellErrorDomain code:LARemoteShellErrorNotConfigured userInfo:@{NSLocalizedDescriptionKey: msg}];
        }
        return nil;
    }
    NSString *receipt = nil;
    NSError *hErr = nil;
    BOOL ok = [self.handoff deliverRequest:request config:cfg receiptId:&receipt error:&hErr];
    if (!ok) {
        if (error) { *error = hErr ?: [NSError errorWithDomain:LARemoteShellErrorDomain code:LARemoteShellErrorNotConfigured userInfo:@{NSLocalizedDescriptionKey: @"远端投递失败。"}]; }
        return nil;
    }
    LARemoteShellResult *r = [[LARemoteShellResult alloc] init];
    r.executed = YES;
    r.channel = channel;
    r.receiptId = receipt;
    r.userGuidance = @"已经用户确认通道下发远端执行，回执见 receiptId（全程应记入 trajectory）。";
    return r;
}

@end
