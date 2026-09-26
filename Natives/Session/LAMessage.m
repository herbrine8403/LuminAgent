#import "LAMessage.h"
#import "LAMessagePart.h"

/* 消息模型实现 */

@implementation LAMessage

+ (instancetype)messageWithSessionID:(NSString *)sessionID role:(LAMessageRole)role {
    LAMessage *message = [[LAMessage alloc] init];
    message.messageID = [[NSUUID UUID] UUIDString];
    message.sessionID = [sessionID copy] ?: @"";
    message.role = role;
    message.createdAt = [[NSDate date] timeIntervalSince1970];
    message.parts = [NSMutableArray array];
    return message;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _parts = [NSMutableArray array];
    }
    return self;
}

- (void)appendPart:(LAMessagePart *)part {
    if (part) {
        [self.parts addObject:part];
    }
}

- (long long)totalTokens {
    long long total = 0;
    for (LAMessagePart *part in self.parts) {
        total += part.tokens;
    }
    return total;
}

- (long long)totalCostMicro {
    long long total = 0;
    for (LAMessagePart *part in self.parts) {
        total += part.costMicro;
    }
    return total;
}

+ (NSString *)stringForRole:(LAMessageRole)role {
    switch (role) {
        case LAMessageRoleUser:      return @"user";
        case LAMessageRoleAssistant: return @"assistant";
        case LAMessageRoleTool:      return @"tool";
        case LAMessageRoleSystem:    return @"system";
    }
    return @"user";
}

+ (LAMessageRole)roleForString:(NSString *)string {
    if ([string isEqualToString:@"assistant"]) return LAMessageRoleAssistant;
    if ([string isEqualToString:@"tool"])      return LAMessageRoleTool;
    if ([string isEqualToString:@"system"])    return LAMessageRoleSystem;
    return LAMessageRoleUser;
}

- (NSDictionary *)toDictionary {
    NSMutableArray *partDicts = [NSMutableArray arrayWithCapacity:self.parts.count];
    for (LAMessagePart *part in self.parts) {
        [partDicts addObject:[part toDictionary]];
    }
    return @{
        @"id": self.messageID ?: @"",
        @"role": [[self class] stringForRole:self.role],
        @"createdAt": @(self.createdAt),
        @"reverted": @(self.reverted),
        @"parts": [partDicts copy],
    };
}

- (instancetype)initWithDictionary:(NSDictionary *)dict sessionID:(NSString *)sessionID {
    self = [super init];
    if (self) {
        _messageID = [dict[@"id"] copy] ?: [[NSUUID UUID] UUIDString];
        _sessionID = [sessionID copy] ?: [dict[@"sessionID"] copy] ?: @"";
        _role = [[self class] roleForString:dict[@"role"]];
        _createdAt = [dict[@"createdAt"] doubleValue];
        _reverted = [dict[@"reverted"] boolValue];
        _parts = [NSMutableArray array];
        for (NSDictionary *partDict in dict[@"parts"]) {
            if ([partDict isKindOfClass:[NSDictionary class]]) {
                LAMessagePart *part = [[LAMessagePart alloc] initWithDictionary:partDict];
                [_parts addObject:part];
            }
        }
    }
    return self;
}

@end
