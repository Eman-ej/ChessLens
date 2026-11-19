// ChessLens integration, GPL-3.0-or-later.
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface StockfishBridge : NSObject
- (nullable NSString *)analyzeFEN:(NSString *)fen
                    milliseconds:(NSInteger)milliseconds
                           error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(analyze(fen:milliseconds:));
- (void)stop;
@end
NS_ASSUME_NONNULL_END
