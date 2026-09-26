#ifndef APP_DELEGATE_H
#define APP_DELEGATE_H

#import <UIKit/UIKit.h>

// 应用级代理：负责应用生命周期回调与主窗口兜底创建（iOS 13 以下）。
@interface AppDelegate : UIResponder <UIApplicationDelegate>

// 主窗口（iOS 13+ 由 SceneDelegate 接管，此处保留兼容）。
@property (strong, nonatomic) UIWindow *window;

@end

#endif /* APP_DELEGATE_H */
