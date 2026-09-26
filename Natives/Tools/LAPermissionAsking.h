#ifndef LA_PERMISSION_ASKING_H
#define LA_PERMISSION_ASKING_H

#import <Foundation/Foundation.h>

// 权限问询契约（Tools 组唯一真源）：UI 由他组实现，此处仅通过回调请求 ask。
// 约定：工具层不直接弹框，只调用回调；UI 线程由实现方保证。
// Session 组权限中心（Session/LAPermissionCenter.h）采用本协议并复用下述枚举，
// 全工程不再另行定义权限裁决枚举。

// 权限裁决三态：需追问 / 本次同意 / 本次拒绝。
typedef NS_ENUM(NSInteger, LAPermissionDecision) {
    LAPermissionDecisionAsk   = 0, // 需要用户确认（默认）
    LAPermissionDecisionAllow = 1, // 本次同意
    LAPermissionDecisionDeny  = 2, // 本次拒绝
};

// 权限请求上下文：工具名 + 目标 + 原因，供权限卡展示。
@interface LAPermissionRequest : NSObject
@property (nonatomic, copy) NSString *toolName;   // 如 @"read" / @"remote-shell"
@property (nonatomic, copy) NSString *targetPath; // 目标路径或命令摘要
@property (nonatomic, copy) NSString *reason;     // 中文原因说明
+ (instancetype)requestWithTool:(NSString *)tool target:(NSString *)target reason:(NSString *)reason;
@end

// 仅 ask 回调协议：返回 Allow 则继续，Deny/Ask-拒绝则返回 denied 错误。
@protocol LAPermissionAsking <NSObject>
@required
// 同步 ask（实现方可内部转异步后阻塞回调，或直接返回预设规则结果）。
- (LAPermissionDecision)askPermission:(LAPermissionRequest *)request;
@end

#endif /* LA_PERMISSION_ASKING_H */
