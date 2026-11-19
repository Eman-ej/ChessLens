// ChessLens integration, GPL-3.0-or-later.
#import "StockfishBridge.h"
#import <CommonCrypto/CommonDigest.h>
#import <TargetConditionals.h>
#include <stdexcept>
#include "NativeEngine.hpp"
#include <exception>
#include <memory>

@implementation StockfishBridge {
    std::unique_ptr<ChessLens::NativeEngine> _nativeEngine;
    NSString *_verifiedNetworkPath;
}
- (instancetype)init {
    self = [super init];
    if (self) _nativeEngine = std::make_unique<ChessLens::NativeEngine>();
    return self;
}
- (NSString *)analyzeFEN:(NSString *)fen milliseconds:(NSInteger)milliseconds error:(NSError **)error {
    @autoreleasepool {
        try {
            if (!_verifiedNetworkPath) {
                NSString *path = [[NSBundle mainBundle] pathForResource:@"nn-1a298aa575a0" ofType:@"nnue"];
                // Environment path is accepted only by the standalone macOS test harness.
#if TARGET_OS_OSX
                if (!path) path = [NSProcessInfo processInfo].environment[@"CHESSLENS_STOCKFISH_NETWORK"];
#endif
                NSData *bytes = path ? [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil] : nil;
                if (!bytes) throw std::runtime_error("The bundled Stockfish network is missing.");
                unsigned char digest[CC_SHA256_DIGEST_LENGTH];
                CC_SHA256(bytes.bytes, (CC_LONG)bytes.length, digest);
                NSMutableString *hex = [NSMutableString string];
                for (int index = 0; index < CC_SHA256_DIGEST_LENGTH; ++index) [hex appendFormat:@"%02x", digest[index]];
                if (![hex isEqualToString:@"1a298aa575a085434d29027978dc36867fe9c5bcea9376654b7a8eba1e52dfc2"])
                    throw std::runtime_error("The bundled Stockfish network failed its integrity check.");
                _verifiedNetworkPath = path;
            }
            auto text = _nativeEngine->analyze(fen.UTF8String, (int)milliseconds, _verifiedNetworkPath.fileSystemRepresentation);
            return [[NSString alloc] initWithBytes:text.data() length:text.size() encoding:NSUTF8StringEncoding];
        } catch (const std::exception& exception) {
            if (error) *error = [NSError errorWithDomain:@"ChessLens.Stockfish" code:1
                userInfo:@{NSLocalizedDescriptionKey: @(exception.what())}];
            return nil;
        }
    }
}
- (void)stop { _nativeEngine->stop(); }
@end
