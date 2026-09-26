#import "LAErrors.h"

/* 错误域实现 */

NSString * const LAErrorDomain = @"com.luminagent.ios";

NSError *LAErrorWithCode(LAErrorCode code, NSString *desc) {
    NSString *message = desc;
    if (message == nil || message.length == 0) {
        switch (code) {
            case LAErrorCodeStoreFailure:     message = @"存储层读写失败"; break;
            case LAErrorCodeNotFound:         message = @"对象不存在"; break;
            case LAErrorCodePlanDenied:       message = @"Plan 模式拒绝写操作，已记录取消事件"; break;
            case LAErrorCodePermissionDenied: message = @"权限被拒绝，已记录取消事件"; break;
            case LAErrorCodeDoomLoop:         message = @"检测到循环调用，已暂停等待确认"; break;
            case LAErrorCodeTodoConflict:     message = @"已存在进行中的 Todo，一次仅允许一个"; break;
            case LAErrorCodeDepthExceeded:    message = @"子代理嵌套层数超限"; break;
            case LAErrorCodeImportInvalid:    message = @"导入数据非法或版本不支持"; break;
            case LAErrorCodeImageTooLarge:    message = @"图片超限，请先下采样"; break;
            case LAErrorCodeAborted:          message = @"会话运行已被中断"; break;
            default:                          message = @"未知错误"; break;
        }
    }
    return [NSError errorWithDomain:LAErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}
