// ChessLens integration, GPL-3.0-or-later (links Stockfish).
#include "NativeEngine.hpp"
#include "vendor/src/attacks.h"
#include "vendor/src/engine.h"
#include "vendor/src/position.h"
#include "vendor/src/uci.h"
#include <algorithm>
#include <filesystem>
#include <sstream>
#include <stdexcept>

namespace ChessLens {
NativeEngine::NativeEngine() = default;
NativeEngine::~NativeEngine() { stop(); }
void NativeEngine::stop() {
    cancelled.store(true);
    if (auto* running = active.load()) running->stop();
}
std::string NativeEngine::analyze(const std::string& fen, int milliseconds, const std::string& networkPath) {
    std::lock_guard<std::mutex> lock(searchMutex);
    cancelled.store(false);
    static std::once_flag initialized;
    std::call_once(initialized, [] { Stockfish::Attacks::init(); Stockfish::Position::init(); });
    if (!engine) {
        if (!std::filesystem::is_regular_file(networkPath))
            throw std::runtime_error("Stockfish evaluation network is missing from the app.");
        engine = std::make_unique<Stockfish::Engine>();
        auto option = [&](const std::string& name, const std::string& value) {
            std::istringstream command("name " + name + " value " + value);
            engine->get_options().setoption(command);
        };
        option("EvalFile", networkPath);
        option("Threads", "1");
        option("Hash", "16");
        option("MultiPV", "3");
        engine->set_on_iter([](const auto&) {});
        engine->set_on_start([] {});
        // A missing or incompatible network must never terminate the iOS process.
        engine->set_on_verify_network([](std::string_view text) {
            if (text.find("ERROR:") != std::string_view::npos)
                throw std::runtime_error("Stockfish evaluation network could not be loaded.");
        });
    }
    if (auto error = engine->set_position(fen, {})) throw std::runtime_error(error->what());
    std::ostringstream transcript;
    transcript << "id name Stockfish 19 local\n";
    engine->set_on_update_no_moves([&](const Stockfish::Engine::InfoShort& info) {
        transcript << "info depth " << info.depth << " score " << Stockfish::UCIEngine::format_score(info.score) << "\n";
    });
    engine->set_on_update_full([&](const Stockfish::Engine::InfoFull& info) {
        transcript << "info depth " << info.depth << " multipv " << info.multiPV
                   << " score " << Stockfish::UCIEngine::format_score(info.score);
        if (!info.bound.empty()) transcript << " " << info.bound;
        transcript << " nodes " << info.nodes << " time " << info.timeMs << " pv " << info.pv << "\n";
    });
    engine->set_on_bestmove([&](std::string_view best, std::string_view ponder) {
        transcript << "bestmove " << best;
        if (!ponder.empty()) transcript << " ponder " << ponder;
        transcript << "\n";
    });
    if (cancelled.load()) throw std::runtime_error("Analysis cancelled.");
    Stockfish::Search::LimitsType limits;
    limits.startTime = Stockfish::now();
    limits.movetime = std::clamp(milliseconds, 50, 10000);
    active.store(engine.get());
    try {
        engine->go(limits);
        if (cancelled.load()) engine->stop();
        engine->wait_for_search_finished();
        active.store(nullptr);
    } catch (...) {
        active.store(nullptr);
        throw;
    }
    return transcript.str();
}
}
