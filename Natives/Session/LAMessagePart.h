#ifndef LA_MESSAGE_PART_H
#define LA_MESSAGE_PART_H

/* 消息 part 模型：一条消息由多个 part 组成，覆盖文本/推理/工具/文件/
 * 代理/子任务/快照/补丁/摘要等类型，并携带 token 与费用元数据。 */

#import <Foundation/Foundation.h>

/* part 类型：text/reasoning/tool/file/agent/subtask/snapshot/patch 为规约必备，
 * summary 供压缩器使用，question/event 供问卷与轨迹事件使用。 */
typedef NS_ENUM(NSInteger, LAMessagePartKind) {
    LAMessagePartKindText,       /* 普通文本 */
    LAMessagePartKindReasoning,  /* 推理过程 */
    LAMessagePartKindToolCall,   /* 工具调用请求（含 toolName/toolArguments） */
    LAMessagePartKindToolResult, /* 工具返回结果 */
    LAMessagePartKindFile,       /* 文件引用（含 filePath） */
    LAMessagePartKindAgent,      /* 子代理回传（含 agentName） */
    LAMessagePartKindSubtask,    /* 子任务委派记录 */
    LAMessagePartKindSnapshot,   /* Git 快照点记录 */
    LAMessagePartKindPatch,      /* 文件差异补丁（含 patchText） */
    LAMessagePartKindSummary,    /* 压缩摘要（裁剪后保留的记忆） */
    LAMessagePartKindQuestion,   /* 阻塞式问卷记录 */
    LAMessagePartKindEvent,      /* 取消/干预等事件记录 */
};

@interface LAMessagePart : NSObject

@property (nonatomic, copy) NSString *partID;          /* part 唯一标识 */
@property (nonatomic, assign) LAMessagePartKind kind;  /* part 类型 */
@property (nonatomic, copy) NSString *text;            /* 文本载荷（各类型通用） */
@property (nonatomic, copy) NSString *mimeType;        /* 文件/附件 MIME，可空 */
@property (nonatomic, copy) NSString *filePath;        /* file 类型引用路径，可空 */
@property (nonatomic, copy) NSString *toolName;        /* tool 类型工具名，可空 */
@property (nonatomic, copy) NSString *toolArguments;   /* tool 参数 JSON 字符串，可空 */
@property (nonatomic, copy) NSString *agentName;       /* agent/subtask 类型代理名，可空 */
@property (nonatomic, copy) NSString *patchText;       /* patch 类型差异文本，可空 */
@property (nonatomic, assign) long long tokens;        /* 消耗 token 数 */
@property (nonatomic, assign) long long costMicro;     /* 费用（微单位，免费记 0） */
@property (nonatomic, assign) BOOL neverTrim;          /* YES=压缩时永不裁剪（skill 输出） */
@property (nonatomic, assign) NSTimeInterval createdAt; /* 创建时间戳（秒） */

/* 便捷构造 */
+ (instancetype)partWithKind:(LAMessagePartKind)kind text:(NSString *)text;

/* 类型与字符串互转（落库/export 共用） */
+ (NSString *)stringForKind:(LAMessagePartKind)kind;
+ (LAMessagePartKind)kindForString:(NSString *)string;

/* 序列化（export/落库 meta 共用） */
- (NSDictionary *)toDictionary;
- (instancetype)initWithDictionary:(NSDictionary *)dict;

@end

#endif /* LA_MESSAGE_PART_H */
