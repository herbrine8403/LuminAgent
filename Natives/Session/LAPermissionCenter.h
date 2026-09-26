#ifndef LA_SESSION_PERMISSION_CENTER_H
#define LA_SESSION_PERMISSION_CENTER_H

/* 权限中心：ask/allow/deny 三态 + glob/命令前缀细则；
 * external_directory 越界一律 ask；敏感路径默认 ask；
 * 同工具同参三连触发 doom_loop 干预。
 * 裁决枚举统一复用 Tools 组 LAPermissionDecision（见 Tools/LAPermissionAsking.h），
 * 本头不再自定枚举；本类并采用 LAPermissionAsking 协议（同步快路径）。 */

#import <Foundation/Foundation.h>
#import "Tools/LAPermissionAsking.h"

/* 细则：toolPattern 支持 glob（如 mcp_*）；pathGlob 限定路径；
 * commandPrefix 限定命令前缀；三者同时命中才生效。 */
@interface LAPermissionRule : NSObject <NSCopying>

@property (nonatomic, copy) NSString *toolPattern;   /* 工具名 glob，空=匹配全部 */
@property (nonatomic, copy) NSString *pathGlob;      /* 路径 glob，空=不限 */
@property (nonatomic, copy) NSString *commandPrefix; /* 命令前缀，空=不限 */
@property (nonatomic, assign) LAPermissionDecision decision;

+ (instancetype)ruleWithToolPattern:(NSString *)toolPattern
                            pathGlob:(NSString *)pathGlob
                       commandPrefix:(NSString *)commandPrefix
                            decision:(LAPermissionDecision)decision;

/* 是否命中：tool 必传，path/command 为空表示调用无此维度 */
- (BOOL)matchesTool:(NSString *)tool path:(NSString *)path command:(NSString *)command;

@end

@protocol LAPermissionCenterDelegate;

@interface LAPermissionCenter : NSObject <LAPermissionAsking>

/* 沙盒根目录：path 落在根外即越界（越界一律 ask）；nil 表示未知，一律按越界处理 */
@property (nonatomic, copy) NSString *sandboxRoot;
@property (nonatomic, weak) id<LAPermissionCenterDelegate> delegate;

- (instancetype)initWithSandboxRoot:(NSString *)sandboxRoot;

/* 规则管理：后加优先（倒序匹配） */
- (void)addRule:(LAPermissionRule *)rule;
- (void)removeAllRules;
- (NSArray<LAPermissionRule *> *)allRules;

/* 同步裁决（非 ask 快路径 / 规则预检） */
- (LAPermissionDecision)decisionForTool:(NSString *)tool
                                           path:(NSString *)path
                                        command:(NSString *)command;

/* 异步裁决：Allow/Deny 直接回；Ask 经 delegate 弹卡（无 delegate 则视为拒绝） */
- (void)requestDecisionForTool:(NSString *)tool
                           path:(NSString *)path
                        command:(NSString *)command
                     completion:(void (^)(LAPermissionDecision decision))completion;

/* doom_loop：记录调用并判定是否三连同参；命中后计数清零待用户确认 */
- (void)noteToolCallWithTool:(NSString *)tool arguments:(NSString *)argumentsJSON;
- (BOOL)shouldInterveneForTool:(NSString *)tool arguments:(NSString *)argumentsJSON;
- (void)resetDoomLoopState;

/* 敏感路径表（Keychain/provisioning/私钥等），默认 ask */
+ (NSArray<NSString *> *)sensitivePathGlobs;

@end

@protocol LAPermissionCenterDelegate <NSObject>
@optional
/* 弹卡确认：UI 层弹出权限确认卡，用户选择后调用 completion */
- (void)permissionCenter:(LAPermissionCenter *)center
  needsDecisionForTool:(NSString *)tool
                   path:(NSString *)path
                command:(NSString *)command
             completion:(void (^)(LAPermissionDecision decision))completion;
/* 三连干预通知 */
- (void)permissionCenter:(LAPermissionCenter *)center
 didTriggerDoomLoopForTool:(NSString *)tool
                 arguments:(NSString *)argumentsJSON;
/* 拒绝事件通知（供会话记录取消事件） */
- (void)permissionCenter:(LAPermissionCenter *)center
         didDenyTool:(NSString *)tool
              reason:(NSString *)reason;
@end

#endif /* LA_SESSION_PERMISSION_CENTER_H */
