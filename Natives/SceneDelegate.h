#ifndef SCENE_DELEGATE_H
#define SCENE_DELEGATE_H

#import <UIKit/UIKit.h>

// 场景代理：负责窗口创建与根控制器挂载，转发到 EngineLauncher。
@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>

// 当前场景的主窗口。
@property (strong, nonatomic) UIWindow *window;

@end

#endif /* SCENE_DELEGATE_H */
