#import "AppDelegate.h"
#import "SceneDelegate.h"

// 应用代理实现：启动完成后确保有窗口可用，iOS 13+ 交给 SceneDelegate。
@implementation AppDelegate

// 启动完成回调：初始化引擎无关的轻量状态，返回 YES 继续启动。
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;
    (void)launchOptions;
    NSLog(@"[LuminAgent] 应用启动完成");
    return YES;
}

// 新建 Scene 会话配置：使用 Default Configuration 绑定 SceneDelegate。
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    (void)application;
    (void)connectingSceneSession;
    (void)options;
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"Default Configuration"
                                                                  sessionRole:connectingSceneSession.role];
    config.delegateClass = [SceneDelegate class];
    return config;
}

@end
