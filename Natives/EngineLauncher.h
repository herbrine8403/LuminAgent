#ifndef ENGINE_LAUNCHER_H
#define ENGINE_LAUNCHER_H

#import <UIKit/UIKit.h>

// 引擎启动器：入口链最后一环，负责初始化 Core（存储/插件注册表）并返回根控制器。
@interface EngineLauncher : NSObject

// 全局单例。
+ (instancetype)sharedLauncher;

// 启动引擎并挂载界面：返回会话列表占位根控制器。
- (UIViewController *)launchWithWindow:(UIWindow *)window;

@end

#endif /* ENGINE_LAUNCHER_H */
