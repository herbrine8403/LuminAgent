#import "LASession.h"
#import "LAErrors.h"

/* 会话模型实现 */

const double LAAgentDefaultImageMaxDimension = 2000.0;
const long long LAAgentDefaultImageMaxBytes = 5LL * 1024 * 1024;

@implementation LASession

+ (instancetype)sessionWithTitle:(NSString *)title
                       parentID:(NSString *)parentID
                           mode:(LAAgentMainMode)mode {
    LASession *session = [[LASession alloc] init];
    session.sessionID = [[NSUUID UUID] UUIDString];
    session.parentID = [parentID copy];
    session.title = [title copy] ?: @"新的会话";
    session.mainMode = mode;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    session.createdAt = now;
    session.updatedAt = now;
    session.snapshotEnabled = YES;
    session.tokenLimit = 0;
    session.imageMaxDimension = LAAgentDefaultImageMaxDimension;
    session.imageMaxBytes = LAAgentDefaultImageMaxBytes;
    return session;
}

+ (BOOL)checkImageData:(NSData *)data
         maxDimension:(double)maxDimension
             maxBytes:(long long)maxBytes
                error:(NSError **)error {
    if (data == nil) {
        if (error) {
            *error = LAErrorWithCode(LAErrorCodeImportInvalid, @"图片数据为空");
        }
        return NO;
    }
    /* 字节级守卫：像素级下采样需调用方用 UIImage 重绘，本方法只做上限判定。 */
    if (maxBytes > 0 && (long long)data.length > maxBytes) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"图片 %lld 字节超过上限 %lld，请先下采样至 %gpx 内",
                              (long long)data.length, maxBytes, maxDimension];
            *error = LAErrorWithCode(LAErrorCodeImageTooLarge, desc);
        }
        return NO;
    }
    return YES;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"id"] = self.sessionID ?: @"";
    if (self.parentID) dict[@"parentID"] = self.parentID;
    dict[@"title"] = self.title ?: @"";
    dict[@"mode"] = (self.mainMode == LAAgentMainModePlan) ? @"plan" : @"build";
    dict[@"createdAt"] = @(self.createdAt);
    dict[@"updatedAt"] = @(self.updatedAt);
    dict[@"snapshotEnabled"] = @(self.snapshotEnabled);
    dict[@"tokenLimit"] = @(self.tokenLimit);
    dict[@"imageMaxDimension"] = @(self.imageMaxDimension);
    dict[@"imageMaxBytes"] = @(self.imageMaxBytes);
    return [dict copy];
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _sessionID = [dict[@"id"] copy] ?: [[NSUUID UUID] UUIDString];
        _parentID = [dict[@"parentID"] copy];
        _title = [dict[@"title"] copy] ?: @"新的会话";
        _mainMode = [dict[@"mode"] isEqualToString:@"plan"] ? LAAgentMainModePlan : LAAgentMainModeBuild;
        _createdAt = [dict[@"createdAt"] doubleValue];
        _updatedAt = [dict[@"updatedAt"] doubleValue];
        _snapshotEnabled = dict[@"snapshotEnabled"] == nil ? YES : [dict[@"snapshotEnabled"] boolValue];
        _tokenLimit = [dict[@"tokenLimit"] longLongValue];
        _imageMaxDimension = dict[@"imageMaxDimension"] == nil
            ? LAAgentDefaultImageMaxDimension : [dict[@"imageMaxDimension"] doubleValue];
        _imageMaxBytes = dict[@"imageMaxBytes"] == nil
            ? LAAgentDefaultImageMaxBytes : [dict[@"imageMaxBytes"] longLongValue];
    }
    return self;
}

@end
