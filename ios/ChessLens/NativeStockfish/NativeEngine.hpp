// ChessLens integration, GPL-3.0-or-later (links Stockfish).
#pragma once
#include <atomic>
#include <memory>
#include <mutex>
#include <string>
namespace Stockfish { class Engine; }
namespace ChessLens {
class NativeEngine {
public:
    NativeEngine();
    ~NativeEngine();
    std::string analyze(const std::string& fen, int milliseconds, const std::string& networkPath);
    void stop();
private:
    std::mutex searchMutex;
    std::unique_ptr<Stockfish::Engine> engine;
    std::atomic<Stockfish::Engine*> active{nullptr};
    std::atomic<bool> cancelled{false};
};
}
