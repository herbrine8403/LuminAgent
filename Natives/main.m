#import <UIKit/UIKit.h>
#import "AppDelegate.h"

// 应用入口：环境准备（日志/目录）→ UIApplicationMain → AppDelegate。
// 入口链：main → AppDelegate → SceneDelegate → EngineLauncher。

// 未捕获异常处理：记录堆栈后延迟一拍退出，便于日志落盘。
static void LuminUncaughtExceptionHandler(NSException *exception) {
    NSLog(@"[LuminAgent] 未捕获异常: %@", exception.description);
    NSLog(@"[LuminAgent] 调用栈: %@", exception.callStackSymbols);
}

int main(int argc, char *argv[]) {
    // 应用标识（便于日志过滤）
    NSLog(@"[Pre-Init] LuminAgent INIT! Bundle: com.luminagent.ios");

    // 注册异常兜底
    NSSetUncaughtExceptionHandler(&LuminUncaughtExceptionHandler);

    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
