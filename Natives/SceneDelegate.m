#import "SceneDelegate.h"
#import "EngineLauncher.h"

// 场景代理实现：连接成功后创建窗口，经 EngineLauncher 挂载根控制器。
@implementation SceneDelegate

// 场景连接回调：创建窗口并交由 EngineLauncher 启动引擎与界面。
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    (void)session;
    (void)connectionOptions;
    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    // 引擎启动：初始化存储/注册表并挂载会话列表为根控制器
    UIViewController *root = [[EngineLauncher sharedLauncher] launchWithWindow:self.window];
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
    NSLog(@"[LuminAgent] 场景已连接并显示窗口");
}

// 场景进入前台：预留恢复逻辑。
- (void)sceneWillEnterForeground:(UIScene *)scene {
    (void)scene;
}

// 场景进入后台：预留持久化逻辑。
- (void)sceneDidEnterBackground:(UIScene *)scene {
    (void)scene;
}

@end
