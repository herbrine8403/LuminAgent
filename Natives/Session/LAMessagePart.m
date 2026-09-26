#import "LAMessagePart.h"

/* part 模型实现：含类型映射与字典序列化 */

@implementation LAMessagePart

+ (instancetype)partWithKind:(LAMessagePartKind)kind text:(NSString *)text {
    LAMessagePart *part = [[LAMessagePart alloc] init];
    part.partID = [[NSUUID UUID] UUIDString];
    part.kind = kind;
    part.text = text ?: @"";
    part.createdAt = [[NSDate date] timeIntervalSince1970];
    return part;
}

+ (NSString *)stringForKind:(LAMessagePartKind)kind {
    switch (kind) {
        case LAMessagePartKindText:       return @"text";
        case LAMessagePartKindReasoning:  return @"reasoning";
        case LAMessagePartKindToolCall:   return @"tool";
        case LAMessagePartKindToolResult: return @"tool_result";
        case LAMessagePartKindFile:       return @"file";
        case LAMessagePartKindAgent:      return @"agent";
        case LAMessagePartKindSubtask:    return @"subtask";
        case LAMessagePartKindSnapshot:   return @"snapshot";
        case LAMessagePartKindPatch:      return @"patch";
        case LAMessagePartKindSummary:    return @"summary";
        case LAMessagePartKindQuestion:   return @"question";
        case LAMessagePartKindEvent:      return @"event";
    }
    return @"text";
}

+ (LAMessagePartKind)kindForString:(NSString *)string {
    if ([string isEqualToString:@"reasoning"])   return LAMessagePartKindReasoning;
    if ([string isEqualToString:@"tool"])        return LAMessagePartKindToolCall;
    if ([string isEqualToString:@"tool_result"]) return LAMessagePartKindToolResult;
    if ([string isEqualToString:@"file"])        return LAMessagePartKindFile;
    if ([string isEqualToString:@"agent"])       return LAMessagePartKindAgent;
    if ([string isEqualToString:@"subtask"])     return LAMessagePartKindSubtask;
    if ([string isEqualToString:@"snapshot"])    return LAMessagePartKindSnapshot;
    if ([string isEqualToString:@"patch"])       return LAMessagePartKindPatch;
    if ([string isEqualToString:@"summary"])     return LAMessagePartKindSummary;
    if ([string isEqualToString:@"question"])    return LAMessagePartKindQuestion;
    if ([string isEqualToString:@"event"])       return LAMessagePartKindEvent;
    return LAMessagePartKindText;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"id"] = self.partID ?: @"";
    dict[@"kind"] = [[self class] stringForKind:self.kind];
    dict[@"text"] = self.text ?: @"";
    if (self.mimeType)      dict[@"mimeType"] = self.mimeType;
    if (self.filePath)      dict[@"filePath"] = self.filePath;
    if (self.toolName)      dict[@"toolName"] = self.toolName;
    if (self.toolArguments) dict[@"toolArguments"] = self.toolArguments;
    if (self.agentName)     dict[@"agentName"] = self.agentName;
    if (self.patchText)     dict[@"patchText"] = self.patchText;
    dict[@"tokens"] = @(self.tokens);
    dict[@"costMicro"] = @(self.costMicro);
    dict[@"neverTrim"] = @(self.neverTrim);
    dict[@"createdAt"] = @(self.createdAt);
    return [dict copy];
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _partID = [dict[@"id"] copy] ?: [[NSUUID UUID] UUIDString];
        _kind = [[self class] kindForString:dict[@"kind"]];
        _text = [dict[@"text"] copy] ?: @"";
        _mimeType = [dict[@"mimeType"] copy];
        _filePath = [dict[@"filePath"] copy];
        _toolName = [dict[@"toolName"] copy];
        _toolArguments = [dict[@"toolArguments"] copy];
        _agentName = [dict[@"agentName"] copy];
        _patchText = [dict[@"patchText"] copy];
        _tokens = [dict[@"tokens"] longLongValue];
        _costMicro = [dict[@"costMicro"] longLongValue];
        _neverTrim = [dict[@"neverTrim"] boolValue];
        _createdAt = [dict[@"createdAt"] doubleValue];
    }
    return self;
}

@end
