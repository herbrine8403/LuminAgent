#import "LACompaction.h"
#import "LAMessage.h"
#import "LAMessagePart.h"
#import "LATodoStore.h"

/* 压缩实现：纯本地裁剪 + 提示词构造 */

const long long LACompactionDefaultTokenLimit = 100000;
const double LACompactionDefaultThresholdRatio = 0.8;
const NSUInteger LACompactionDefaultRecentKept = 4;

@implementation LACompaction

- (instancetype)init {
    return [self initWithTokenLimit:LACompactionDefaultTokenLimit
                     thresholdRatio:LACompactionDefaultThresholdRatio
                         recentKept:LACompactionDefaultRecentKept];
}

- (instancetype)initWithTokenLimit:(long long)tokenLimit
                    thresholdRatio:(double)ratio
                        recentKept:(NSUInteger)recentKept {
    self = [super init];
    if (self) {
        _tokenLimit = tokenLimit > 0 ? tokenLimit : LACompactionDefaultTokenLimit;
        _thresholdRatio = (ratio > 0 && ratio <= 1) ? ratio : LACompactionDefaultThresholdRatio;
        _recentKept = recentKept;
    }
    return self;
}

- (BOOL)needsCompactionForTokenCount:(long long)tokenCount {
    return tokenCount >= (long long)(self.tokenLimit * self.thresholdRatio);
}

- (long long)tokenCountForMessages:(NSArray<LAMessage *> *)messages {
    long long total = 0;
    for (LAMessage *message in messages) {
        total += [message totalTokens];
    }
    return total;
}

- (NSString *)buildCompactionPromptForMessages:(NSArray<LAMessage *> *)messages
                                         todos:(NSArray<LATodo *> *)todos {
    NSMutableString *prompt = [NSMutableString stringWithString:
        @"请将以下会话压缩为一段中文摘要，保留：用户目标、已完成步骤、当前 Todo 状态、关键文件路径与决策。工具原始输出可省略，但 skill 输出要点必须保留。\n"];
    for (LATodo *todo in todos) {
        NSString *mark = @"[待办]";
        if (todo.status == LATodoStatusInProgress) mark = @"[进行中]";
        if (todo.status == LATodoStatusCompleted)  mark = @"[已完成]";
        [prompt appendFormat:@"\n%@ %@", mark, todo.content];
    }
    [prompt appendString:@"\n\n--- 会话内容 ---\n"];
    for (LAMessage *message in messages) {
        for (LAMessagePart *part in message.parts) {
            /* 提示词中同样豁免 skill 输出的裁剪：全文保留 neverTrim 文本 */
            NSString *text = part.text ?: @"";
            if (!part.neverTrim && text.length > 500 &&
                (part.kind == LAMessagePartKindToolResult ||
                 part.kind == LAMessagePartKindToolCall)) {
                text = [[text substringToIndex:500] stringByAppendingString:@"…（已截断）"];
            }
            [prompt appendFormat:@"\n[%@/%@] %@\n",
             [LAMessage stringForRole:message.role],
             [LAMessagePart stringForKind:part.kind], text];
        }
    }
    return [prompt copy];
}

/* 旧工具输出是否可裁：tool_result/tool_call 且非永不裁剪 */
- (BOOL)shouldTrimPart:(LAMessagePart *)part {
    if (part.neverTrim) {
        return NO;
    }
    return part.kind == LAMessagePartKindToolResult || part.kind == LAMessagePartKindToolCall;
}

- (NSArray<LAMessage *> *)applySummary:(NSString *)summary
                             toMessages:(NSArray<LAMessage *> *)messages {
    if (messages.count == 0) {
        return @[];
    }
    NSUInteger keepFrom = messages.count > self.recentKept
        ? messages.count - self.recentKept : 0;
    NSMutableArray<LAMessage *> *result = [NSMutableArray array];
    /* 头部插入摘要消息（session 归属与首条一致） */
    LAMessage *first = messages[0];
    LAMessage *summaryMessage = [LAMessage messageWithSessionID:first.sessionID
                                                           role:LAMessageRoleSystem];
    LAMessagePart *summaryPart = [LAMessagePart partWithKind:LAMessagePartKindSummary
                                                        text:summary ?: @"（空摘要）"];
    summaryPart.neverTrim = YES;
    [summaryMessage appendPart:summaryPart];
    [result addObject:summaryMessage];
    /* 中段：保留 neverTrim 与非工具输出，裁剪旧工具输出 */
    for (NSUInteger i = 0; i < keepFrom; i++) {
        LAMessage *source = messages[i];
        /* 首条系统提示原样保留（守住指令） */
        if (i == 0 && source.role == LAMessageRoleSystem) {
            [result addObject:source];
            continue;
        }
        LAMessage *kept = [LAMessage messageWithSessionID:source.sessionID role:source.role];
        kept.messageID = source.messageID;
        kept.createdAt = source.createdAt;
        for (LAMessagePart *part in source.parts) {
            if ([self shouldTrimPart:part]) {
                /* 裁剪为占位，保留工具名可追溯 */
                NSString *note = [NSString stringWithFormat:@"（已压缩，工具 %@ 输出省略%@）",
                                  part.toolName ?: @"未知",
                                  part.neverTrim ? @"（skill 保留）" : @""];
                LAMessagePart *placeholder = [LAMessagePart partWithKind:part.kind text:note];
                placeholder.toolName = part.toolName;
                placeholder.tokens = 0;
                [kept appendPart:placeholder];
            } else {
                [kept appendPart:part];
            }
        }
        [result addObject:kept];
    }
    /* 尾部原样保留 */
    for (NSUInteger i = keepFrom; i < messages.count; i++) {
        [result addObject:messages[i]];
    }
    return [result copy];
}

- (NSArray<LAMessage *> *)compactManuallyWithMessages:(NSArray<LAMessage *> *)messages
                                              summary:(NSString *)summary {
    return [self applySummary:summary toMessages:messages];
}

@end
