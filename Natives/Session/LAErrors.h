#ifndef LA_ERRORS_H
#define LA_ERRORS_H

/* 统一错误域与错误码：Session 组所有公开 API 经 NSError** 回传错误。
 * 中文描述由调用方在构造时传入，本头仅提供错误码与便捷构造。 */

#import <Foundation/Foundation.h>

/* 错误域：com.luminagent.ios */
extern NSString * const LAErrorDomain;

/* 错误码表 */
typedef NS_ENUM(NSInteger, LAErrorCode) {
    LAErrorCodeStoreFailure     = 1001, /* 存储层失败（SQLite 读写/迁移异常） */
    LAErrorCodeNotFound         = 1002, /* 会话/消息/Todo 不存在 */
    LAErrorCodePlanDenied       = 1003, /* Plan 模式拒绝 write/edit/bash（附带取消事件） */
    LAErrorCodePermissionDenied = 1004, /* 权限中心拒绝（附带取消事件） */
    LAErrorCodeDoomLoop         = 1005, /* 同工具同参三连触发干预 */
    LAErrorCodeTodoConflict     = 1006, /* 已存在 in_progress，违反单活跃约束 */
    LAErrorCodeDepthExceeded    = 1007, /* subagent_depth 超出上限 */
    LAErrorCodeImportInvalid    = 1008, /* 导入 JSON 非法或版本不支持 */
    LAErrorCodeImageTooLarge    = 1009, /* 图片超限，需调用方先下采样再归一化 */
    LAErrorCodeAborted          = 1010, /* 会话运行已被 abort 中断 */
};

/* 便捷构造：desc 为中文描述，可为空（此时使用默认描述）。 */
extern NSError *LAErrorWithCode(LAErrorCode code, NSString *desc);

#endif /* LA_ERRORS_H */
