import Foundation
import Network

/// A tiny HTTP server so any browser on the same network (or tailnet) can download scans.
///
/// Routes:
///   GET /                 HTML list of scans
///   GET /pdf/<uuid>       the scan as a PDF
final class TransferServer: ObservableObject {
    struct Item: Sendable {
        let id: UUID
        let name: String
        let pages: Int
        let date: Date
    }

    @Published private(set) var isRunning = false
    @Published private(set) var addresses: [String] = []
    @Published private(set) var errorMessage: String?

    let port: UInt16 = 8080

    /// Supplies the current list of scans. Called on the server queue.
    var listItems: @Sendable () -> [Item] = { [] }
    /// Produces a PDF file for a scan. Called on the server queue.
    var makePDF: @Sendable (UUID) -> (name: String, data: Data)? = { _ in nil }

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "TransferServer")

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.errorMessage = nil
                        self?.addresses = NetworkAddresses.current()
                    case .failed(let error):
                        self?.errorMessage = error.localizedDescription
                        self?.stop()
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    func refreshAddresses() { addresses = NetworkAddresses.current() }

    // MARK: - HTTP

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8),
                  let line = request.components(separatedBy: "\r\n").first else {
                conn.cancel(); return
            }
            let parts = line.split(separator: " ")
            guard parts.count >= 2, parts[0] == "GET" else {
                self.send(conn, status: "405 Method Not Allowed", type: "text/plain", body: Data("Method not allowed".utf8))
                return
            }
            self.route(path: String(parts[1]), conn: conn)
        }
    }

    private func route(path: String, conn: NWConnection) {
        if path == "/" || path.hasPrefix("/?") {
            send(conn, status: "200 OK", type: "text/html; charset=utf-8", body: Data(indexPage().utf8))
        } else if path.hasPrefix("/pdf/"), let id = UUID(uuidString: String(path.dropFirst(5))),
                  let pdf = makePDF(id) {
            let fileName = pdf.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "scan.pdf"
            send(conn, status: "200 OK", type: "application/pdf", body: pdf.data,
                 extraHeaders: ["Content-Disposition": "attachment; filename*=UTF-8''\(fileName)"])
        } else {
            send(conn, status: "404 Not Found", type: "text/plain", body: Data("Not found".utf8))
        }
    }

    private func send(_ conn: NWConnection, status: String, type: String, body: Data, extraHeaders: [String: String] = [:]) {
        var head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n"
        for (k, v) in extraHeaders { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func indexPage() -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        let rows = listItems().map { item in
            """
            <li><a href="/pdf/\(item.id.uuidString)">\(escape(item.name))</a>
            <span>\(item.pages) page\(item.pages == 1 ? "" : "s") · \(df.string(from: item.date))</span></li>
            """
        }.joined(separator: "\n")
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>DocScanner</title>
        <style>
        body{font-family:-apple-system,Segoe UI,sans-serif;max-width:640px;margin:40px auto;padding:0 16px;color:#222;background:#fafafa}
        h1{font-size:22px} ul{list-style:none;padding:0}
        li{background:#fff;border:1px solid #e3e3e3;border-radius:10px;padding:14px 16px;margin:10px 0}
        a{font-weight:600;color:#0a66d8;text-decoration:none;display:block}
        span{color:#777;font-size:13px}
        </style></head><body>
        <h1>Scans on your iPhone</h1>
        \(rows.isEmpty ? "<p>No scans yet.</p>" : "<ul>\(rows)</ul>")
        <p><span>Click a scan to download it as a PDF. Refresh to see new scans.</span></p>
        </body></html>
        """
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Lists this device's IPv4 addresses on Wi‑Fi (en*) and VPN tunnels such as Tailscale (utun*, 100.x).
enum NetworkAddresses {
    static func current() -> [String] {
        var result: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("utun") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: host)
                if !ip.hasPrefix("169.254"), !result.contains(ip) { result.append(ip) }
            }
        }
        return result
    }
}
