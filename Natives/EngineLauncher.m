#import "EngineLauncher.h"
#import "Core/AirCore.h"
#import "UI/LASessionListVC.h"

// 引擎启动器实现：单例 + 会话列表根控制器。
@implementation EngineLauncher

// 获取全局单例（线程安全）。
+ (instancetype)sharedLauncher {
    static EngineLauncher *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[EngineLauncher alloc] init];
    });
    return shared;
}

// 启动流程：初始化插件注册表 → 创建占位根控制器返回。
- (UIViewController *)launchWithWindow:(UIWindow *)window {
    (void)window;
    NSLog(@"[LuminAgent] 引擎启动 Core 版本: %s", AirCoreVersion());
    // 初始化插件注册表（占位实现，后续加载 JSON 清单）
    AirPluginRegistryInit();

    // 根界面：会话列表（含 Bento 引导卡）
    LASessionListVC *root = [[LASessionListVC alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
    return nav;
}

@end
