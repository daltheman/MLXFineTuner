import Foundation

/// Converts CSV, TXT, and PDF files into the `train.jsonl` / `valid.jsonl` format expected by `mlx_lm`.
///
/// Each conversion spawns a Python subprocess that reads the source file and writes JSONL output.
class DatasetConverterService {

    enum OutputFormat: String, CaseIterable, Hashable {
        case chat       = "chat"
        case completion = "completion"
        case text       = "text"

        var displayName: String {
            switch self {
            case .chat:       return "Chat (messages array)"
            case .completion: return "Completion (prompt / completion)"
            case .text:       return "Text (concatenated)"
            }
        }
    }

    // MARK: - CSV Headers

    /// Returns column headers from the first line of a CSV file (Swift-side, no subprocess).
    func csvHeaders(at url: URL) throws -> [String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let firstLine = text.components(separatedBy: "\n").first ?? ""
        return parseCSVRow(firstLine).filter { !$0.isEmpty }
    }

    // MARK: - Conversion

    /// Converts a CSV file to train.jsonl (+ valid.jsonl) via a Python subprocess.
    /// Paths are passed as argv to avoid shell-escaping issues.
    func convertCSV(
        at sourceURL: URL,
        outputDir: URL,
        promptColumn: String,
        responseColumn: String,
        format: OutputFormat = .chat,
        validationSplit: Double = 0.1,
        pythonPath: String
    ) throws {
        let script = """
import sys, csv, json, pathlib, random

src, out_dir, prompt_col, resp_col, fmt, split = \
    sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], float(sys.argv[6])

out = pathlib.Path(out_dir)
out.mkdir(parents=True, exist_ok=True)

def to_row(row):
    p, r = row.get(prompt_col, ''), row.get(resp_col, '')
    if fmt == 'chat':
        return {"messages": [{"role": "user", "content": p}, {"role": "assistant", "content": r}]}
    elif fmt == 'completion':
        return {"prompt": p, "completion": r}
    else:
        return {"text": p + "\\n" + r}

with open(src, newline='', encoding='utf-8') as f:
    rows = list(csv.DictReader(f))

random.shuffle(rows)
n_valid = int(len(rows) * split) if split > 0 else 0
n_valid = min(n_valid, max(0, len(rows) - 1))  # train must keep ≥ 1 row
train_rows, valid_rows = rows[n_valid:], rows[:n_valid]

with open(out / 'train.jsonl', 'w', encoding='utf-8') as f:
    for row in train_rows:
        f.write(json.dumps(to_row(row), ensure_ascii=False) + '\\n')

if valid_rows:
    with open(out / 'valid.jsonl', 'w', encoding='utf-8') as f:
        for row in valid_rows:
            f.write(json.dumps(to_row(row), ensure_ascii=False) + '\\n')

print(f"Converted {len(train_rows)} train + {len(valid_rows)} valid rows → {out_dir}")
"""
        let process = Process()
        let errPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            pythonPath, "-c", script,
            sourceURL.path,
            outputDir.path,
            promptColumn,
            responseColumn,
            format.rawValue,
            "\(validationSplit)"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe
        process.environment = enrichedEnv()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
            throw NSError(
                domain: "DatasetConverter",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }
    }

    // MARK: - PDF Chunker

    /// Extracts text from a PDF with PyMuPDF, cleans headers/footers, then chunks like TXT.
    func convertPDF(
        at sourceURL: URL,
        outputDir: URL,
        chunkTokens: Int = 512,
        overlapTokens: Int = 64,
        validationSplit: Double = 0.1,
        pythonPath: String
    ) throws {
        let script = """
import json, pathlib, random, re, sys, collections

pdf_path, out_dir, chunk_tokens, overlap_tokens, valid_split = \
    sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5])

try:
    import fitz  # PyMuPDF
except ImportError:
    sys.exit("PyMuPDF not found. Run: pip install pymupdf")

CHARS_PER_TOKEN = 4
chunk_chars   = chunk_tokens  * CHARS_PER_TOKEN
overlap_chars = overlap_tokens * CHARS_PER_TOKEN

# --- Extract text per page ---
doc = fitz.open(pdf_path)
pages = [page.get_text("text") for page in doc]
doc.close()

# --- Remove repeated headers/footers (lines appearing in >30% of pages) ---
if len(pages) > 4:
    line_freq = collections.Counter()
    for page in pages:
        for line in page.splitlines():
            s = line.strip()
            if s:
                line_freq[s] += 1
    threshold = max(2, len(pages) * 0.30)
    noise = {line for line, count in line_freq.items() if count >= threshold}
    cleaned = []
    for page in pages:
        lines = [l for l in page.splitlines() if l.strip() not in noise]
        cleaned.append("\\n".join(lines))
    pages = cleaned

text = "\\n\\n".join(pages)
text = re.sub(r'\\r\\n', '\\n', text)
text = re.sub(r'\\n{3,}', '\\n\\n', text)
text = re.sub(r' {2,}', ' ', text)

# --- Soft chunker (same as TXT) ---
def soft_chunks(text, chunk_chars, overlap_chars):
    chunks, start = [], 0
    while start < len(text):
        end = min(start + chunk_chars, len(text))
        if end < len(text):
            mid = start + chunk_chars // 2
            pb = text.rfind('\\n\\n', mid, end)
            if pb != -1:
                end = pb + 2
            else:
                for sep in ['. ', '! ', '? ', '\\n']:
                    sb = text.rfind(sep, mid, end)
                    if sb != -1:
                        end = sb + len(sep)
                        break
        chunk = text[start:end].strip()
        if chunk:
            chunks.append(chunk)
        start = end - overlap_chars if overlap_chars > 0 and end < len(text) else end
    return chunks

chunks = soft_chunks(text, chunk_chars, overlap_chars)
random.shuffle(chunks)

n_valid = int(len(chunks) * valid_split)
n_valid = min(n_valid, max(0, len(chunks) - 1))  # train must keep ≥ 1 chunk
train_chunks, valid_chunks = chunks[n_valid:], chunks[:n_valid]

out = pathlib.Path(out_dir)
out.mkdir(parents=True, exist_ok=True)

with open(out / 'train.jsonl', 'w', encoding='utf-8') as f:
    for c in train_chunks:
        f.write(json.dumps({"text": c}, ensure_ascii=False) + '\\n')

if valid_chunks:
    with open(out / 'valid.jsonl', 'w', encoding='utf-8') as f:
        for c in valid_chunks:
            f.write(json.dumps({"text": c}, ensure_ascii=False) + '\\n')

print(f"Done: {len(train_chunks)} train + {len(valid_chunks)} valid chunks")
print(f"Chunk ~{chunk_tokens} tokens, overlap ~{overlap_tokens} tokens")
"""
        let process = Process()
        let errPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            pythonPath, "-c", script,
            sourceURL.path,
            outputDir.path,
            "\(chunkTokens)",
            "\(overlapTokens)",
            "\(validationSplit)"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe
        process.environment = enrichedEnv()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
            throw NSError(
                domain: "DatasetConverter",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }
    }

    // MARK: - TXT Chunker

    /// Chunks a plain-text file into train.jsonl + valid.jsonl via a Python subprocess.
    /// Uses soft split (paragraph → sentence → hard cut) and character-based token approximation.
    func convertTXT(
        at sourceURL: URL,
        outputDir: URL,
        chunkTokens: Int = 512,
        overlapTokens: Int = 64,
        validationSplit: Double = 0.1,
        pythonPath: String
    ) throws {
        let script = """
import json, pathlib, random, re, sys

txt_path, out_dir, chunk_tokens, overlap_tokens, valid_split = \
    sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5])

CHARS_PER_TOKEN = 4
chunk_chars   = chunk_tokens  * CHARS_PER_TOKEN
overlap_chars = overlap_tokens * CHARS_PER_TOKEN

text = pathlib.Path(txt_path).read_text(encoding='utf-8')
text = re.sub(r'\\r\\n', '\\n', text)
text = re.sub(r'\\n{3,}', '\\n\\n', text)

def soft_chunks(text, chunk_chars, overlap_chars):
    chunks, start = [], 0
    while start < len(text):
        end = min(start + chunk_chars, len(text))
        if end < len(text):
            # 1. Try paragraph break in the second half of the window
            mid = start + chunk_chars // 2
            pb = text.rfind('\\n\\n', mid, end)
            if pb != -1:
                end = pb + 2
            else:
                # 2. Try sentence-ending punctuation
                for sep in ['. ', '! ', '? ', '\\n']:
                    sb = text.rfind(sep, mid, end)
                    if sb != -1:
                        end = sb + len(sep)
                        break
        chunk = text[start:end].strip()
        if chunk:
            chunks.append(chunk)
        start = end - overlap_chars if overlap_chars > 0 and end < len(text) else end
    return chunks

chunks = soft_chunks(text, chunk_chars, overlap_chars)
random.shuffle(chunks)

n_valid = int(len(chunks) * valid_split)
n_valid = min(n_valid, max(0, len(chunks) - 1))  # train must keep ≥ 1 chunk
train_chunks, valid_chunks = chunks[n_valid:], chunks[:n_valid]

out = pathlib.Path(out_dir)
out.mkdir(parents=True, exist_ok=True)

with open(out / 'train.jsonl', 'w', encoding='utf-8') as f:
    for c in train_chunks:
        f.write(json.dumps({"text": c}, ensure_ascii=False) + '\\n')

if valid_chunks:
    with open(out / 'valid.jsonl', 'w', encoding='utf-8') as f:
        for c in valid_chunks:
            f.write(json.dumps({"text": c}, ensure_ascii=False) + '\\n')

print(f"Done: {len(train_chunks)} train + {len(valid_chunks)} valid chunks")
print(f"Chunk ~{chunk_tokens} tokens, overlap ~{overlap_tokens} tokens")
"""
        let process = Process()
        let errPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            pythonPath, "-c", script,
            sourceURL.path,
            outputDir.path,
            "\(chunkTokens)",
            "\(overlapTokens)",
            "\(validationSplit)"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe
        process.environment = enrichedEnv()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
            throw NSError(
                domain: "DatasetConverter",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }
    }

    // MARK: - Private

    private func parseCSVRow(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            switch char {
            case "\"": inQuotes.toggle()
            case "," where !inQuotes:
                fields.append(current.trimmingCharacters(in: .init(charactersIn: " \"")))
                current = ""
            default: current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .init(charactersIn: " \"")))
        return fields
    }

    private func enrichedEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = ["/usr/local/bin", "/opt/homebrew/bin", "/opt/homebrew/opt/python/bin"]
        env["PATH"] = (extra + [env["PATH"] ?? ""]).joined(separator: ":")
        return env
    }
}
