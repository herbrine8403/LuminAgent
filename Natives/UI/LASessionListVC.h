#ifndef LA_SESSION_LIST_VC_H
#define LA_SESSION_LIST_VC_H

/* 会话列表（Bento CompositionalLayout）：引导大磁贴 + 会话磁贴混排。
 * ≥2 种磁贴尺寸：首会话大磁贴（全宽高 120）+ 普通小磁贴（双列高 96）。
 * 空会话时显示引导卡；chip 按 Build/Plan 过滤。 */

#import <UIKit/UIKit.h>

@class LASession;
@class LASessionListVC;

@protocol LASessionListDelegate <NSObject>
@optional
- (void)sessionList:(LASessionListVC *)list didSelectSession:(LASession *)session;
- (void)sessionListDidTapCreate:(LASessionListVC *)list;
@end

@interface LASessionListVC : UIViewController <UICollectionViewDataSource, UICollectionViewDelegate>

@property (nonatomic, weak) id<LASessionListDelegate> delegate;

/* 会话数据源（LASession 数组，只消费不重复定义） */
- (void)reloadWithSessions:(NSArray<LASession *> *)sessions;

/* 三态：加载骨架 / 空引导 / 错误重试 */
- (void)showLoading;
- (void)showErrorWithRetryTarget:(id)target action:(SEL)action;

@end

#endif /* LA_SESSION_LIST_VC_H */
