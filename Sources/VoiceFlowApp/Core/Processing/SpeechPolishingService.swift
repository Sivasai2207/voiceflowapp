import Foundation
import AppKit
import OSLog

public final class SpeechPolishingService: Sendable {
    public static let shared = SpeechPolishingService()
    
    private let logger = Logger(subsystem: "VoiceFlowApp", category: "SpeechPolishingService")
    
    private init() {}
    
    /// Polishes raw speech transcription into clean, natural, error-free prose (Wispr Flow style).
    func polish(
        transcript: String,
        autoPunctuation: Bool = true,
        dictionaryEntries: [DictionaryEntry] = []
    ) -> String {
        var text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        
        // 1. Remove spoken disfluencies (fillers: um, uh, ah, etc.)
        text = removeFillerWords(text)
        
        // 2. Remove stutters & duplicate consecutive words ("the the" -> "the", "I I" -> "I")
        text = removeStutters(text)
        
        // 3. Convert verbal punctuation commands ("period", "comma", "question mark")
        text = convertSpokenPunctuation(text)
        
        // 4. Restore contractions ("dont" -> "don't", "im" -> "I'm", "thats" -> "that's")
        text = restoreContractions(text)
        
        // 5. Clean up whitespace and punctuation spacing
        text = cleanSpacingAndPunctuation(text)
        
        // 6. Spellcheck & typo correction
        text = correctSpellingAndGrammar(text)
        
        // 7. Capitalization (sentence start, "I", acronyms)
        text = applySmartCapitalization(text)

        // 8. Apply explicit, local user corrections after spell checking so custom terms win.
        text = applyDictionaryEntries(dictionaryEntries, to: text)
        
        // 9. Terminal punctuation (period or question mark) if autoPunctuation is enabled
        if autoPunctuation {
            text = applyTerminalPunctuation(text)
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applyDictionaryEntries(_ entries: [DictionaryEntry], to text: String) -> String {
        entries
            .sorted { $0.word.count > $1.word.count }
            .reduce(text) { result, entry in
                let pattern = referenceWordPattern(for: entry.word)
                return result.replacingOccurrences(of: pattern, with: entry.word, options: .regularExpression)
            }
    }

    private func referenceWordPattern(for word: String) -> String {
        let separatedWords = word.replacingOccurrences(
            of: "([a-z])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )
        let escapedComponents = separatedWords
            .split(whereSeparator: { $0.isWhitespace })
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
        let flexibleSpacing = escapedComponents.joined(separator: "\\s*")
        return "(?i)(?<![\\p{L}\\p{N}])\(flexibleSpacing)(?![\\p{L}\\p{N}])"
    }
    
    // MARK: - 1. Filler Word Removal
    private func removeFillerWords(_ text: String) -> String {
        // Remove hesitations like: um, uh, uhm, erm, er, ah, ahh, hmm
        let fillerRegex = #"(?i)\b(um+|uh+|uhm+|erm+|er+|ah+|ahh+|hmm+)\b"#
        var cleaned = text.replacingOccurrences(of: fillerRegex, with: "", options: .regularExpression)
        
        // Clean isolated conversational filler phrases at clause boundaries
        let phraseFillers = [
            #"(?i)^\s*(you know|i mean|like)\s*,\s*"#: "",
            #"(?i),\s*(you know|i mean)\s*,"#: ",",
            #"(?i)\b(you know|i mean)\s*$"#: ""
        ]
        
        for (pattern, replacement) in phraseFillers {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        
        return cleaned
    }
    
    // MARK: - 2. Stutter and Duplicate Word Removal
    private func removeStutters(_ text: String) -> String {
        // Matches consecutive duplicate words case-insensitively (e.g., "I I" -> "I", "the the" -> "the")
        let stutterRegex = #"(?i)\b([a-zA-Z]+)\s+\1\b"#
        var result = text
        
        // Run twice to catch triple repeats ("the the the" -> "the")
        for _ in 0..<2 {
            result = result.replacingOccurrences(of: stutterRegex, with: "$1", options: .regularExpression)
        }
        
        return result
    }
    
    // MARK: - 3. Spoken Punctuation Parser
    private func convertSpokenPunctuation(_ text: String) -> String {
        var result = text
        
        let mappings: [(pattern: String, replacement: String)] = [
            (#"(?i)\s*\b(question mark)\b"#, "?"),
            (#"(?i)\s*\b(exclamation mark|exclamation point)\b"#, "!"),
            (#"(?i)\s*\b(period|full stop)\b"#, "."),
            (#"(?i)\s*\b(comma)\b"#, ","),
            (#"(?i)\s*\b(colon)\b"#, ":"),
            (#"(?i)\s*\b(semicolon)\b"#, ";"),
            (#"(?i)\s*\b(new paragraph)\b"#, "\n\n"),
            (#"(?i)\s*\b(new line|newline)\b"#, "\n"),
            (#"(?i)\s*\b(dash|hyphen)\b"#, " - "),
            (#"(?i)\s*\b(dot dot dot|ellipsis)\b"#, "..."),
            (#"(?i)\b(open quote|quote)\b\s*"#, "\""),
            (#"(?i)\s*\b(close quote|unquote)\b"#, "\"")
        ]
        
        for mapping in mappings {
            result = result.replacingOccurrences(of: mapping.pattern, with: mapping.replacement, options: .regularExpression)
        }
        
        return result
    }
    
    // MARK: - 4. Restore Missing Contractions
    private func restoreContractions(_ text: String) -> String {
        let contractions: [(pattern: String, replacement: String)] = [
            (#"(?i)\b(i)'?m\b"#, "I'm"),
            (#"(?i)\b(i)'?ve\b"#, "I've"),
            (#"(?i)\b(i)'?ll\b"#, "I'll"),
            (#"(?i)\b(i)'?d\b"#, "I'd"),
            (#"(?i)\bdont\b"#, "don't"),
            (#"(?i)\bcant\b"#, "can't"),
            (#"(?i)\bwont\b"#, "won't"),
            (#"(?i)\bdidnt\b"#, "didn't"),
            (#"(?i)\bdoesnt\b"#, "doesn't"),
            (#"(?i)\bisnt\b"#, "isn't"),
            (#"(?i)\barent\b"#, "aren't"),
            (#"(?i)\bwasnt\b"#, "wasn't"),
            (#"(?i)\bwerent\b"#, "weren't"),
            (#"(?i)\bhasnt\b"#, "hasn't"),
            (#"(?i)\bhavent\b"#, "haven't"),
            (#"(?i)\bhadnt\b"#, "hadn't"),
            (#"(?i)\bcouldnt\b"#, "couldn't"),
            (#"(?i)\bshouldnt\b"#, "shouldn't"),
            (#"(?i)\bwouldnt\b"#, "wouldn't"),
            (#"(?i)\bthats\b"#, "that's"),
            (#"(?i)\bwhats\b"#, "what's"),
            (#"(?i)\btheres\b"#, "there's"),
            (#"(?i)\bheres\b"#, "here's"),
            (#"(?i)\blets\b"#, "let's"),
            (#"(?i)\byoure\b"#, "you're"),
            (#"(?i)\btheyre\b"#, "they're"),
            (#"(?i)\bweve\b"#, "we've"),
            (#"(?i)\byouve\b"#, "you've")
        ]
        
        var result = text
        for item in contractions {
            result = result.replacingOccurrences(of: item.pattern, with: item.replacement, options: .regularExpression)
        }
        return result
    }
    
    // MARK: - 5. Clean Spacing & Punctuation
    private func cleanSpacingAndPunctuation(_ text: String) -> String {
        var result = text
        
        // Remove spaces before punctuation (e.g., "hello , world" -> "hello, world")
        result = result.replacingOccurrences(of: #"\s+([,\.\?!:;])"#, with: "$1", options: .regularExpression)
        
        // Ensure single space after punctuation (e.g., "hello.world" -> "hello. world" unless it's a number/URL)
        result = result.replacingOccurrences(of: #"([,\.\?!:;])([a-zA-Z])"#, with: "$1 $2", options: .regularExpression)
        
        // Clean leading commas or dangling punctuation at the start of text
        result = result.replacingOccurrences(of: #"^[\s,;:.]+"#, with: "", options: .regularExpression)
        
        // Clean duplicate punctuation like ",," or ".. "
        result = result.replacingOccurrences(of: #",{2,}"#, with: ",", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?<!\.)\.\.(?!\.)"#, with: ".", options: .regularExpression)
        
        // Collapse multiple spaces
        result = result.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        
        return result
    }
    
    // MARK: - 6. Spell Check and Typo Correction
    private func correctSpellingAndGrammar(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        
        // Use NSSpellChecker for light spelling fix
        let spellChecker = NSSpellChecker.shared
        
        // Check spelling for words
        var result = text
        var searchLocation = 0
        
        while searchLocation < result.utf16.count {
            let subRange = NSRange(location: searchLocation, length: result.utf16.count - searchLocation)
            let misspellingRange = spellChecker.checkSpelling(of: result, startingAt: subRange.location)
            
            if misspellingRange.location == NSNotFound || misspellingRange.location >= result.utf16.count {
                break
            }
            
            // Check if there is a high-confidence correction
            if let guesses = spellChecker.guesses(forWordRange: misspellingRange, in: result, language: nil, inSpellDocumentWithTag: 0),
               let firstGuess = guesses.first,
               guesses.count <= 3 { // High confidence when options are constrained
                
                if let swiftRange = Range(misspellingRange, in: result) {
                    let misspelledWord = String(result[swiftRange])
                    // Only replace if length is similar and not capitalized proper noun
                    if abs(misspelledWord.count - firstGuess.count) <= 2 && misspelledWord != misspelledWord.capitalized {
                        result.replaceSubrange(swiftRange, with: firstGuess)
                        searchLocation = misspellingRange.location + firstGuess.utf16.count
                        continue
                    }
                }
            }
            
            searchLocation = misspellingRange.location + misspellingRange.length
        }
        
        return result
    }
    
    // MARK: - 7. Smart Capitalization
    private func applySmartCapitalization(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        
        var result = text
        
        // Capitalize standalone lowercase "i" -> "I"
        result = result.replacingOccurrences(of: #"\b(i)\b"#, with: "I", options: .regularExpression)
        
        // Capitalize beginning of string
        if let first = result.first, first.isLowercase {
            result = result.prefix(1).uppercased() + result.dropFirst()
        }
        
        // Capitalize character following terminal punctuation (. ! ? \n)
        let sentenceBoundaryRegex = #"([\.\?!\n]\s+)([a-z])"#
        if let regex = try? NSRegularExpression(pattern: sentenceBoundaryRegex) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))
            
            for match in matches.reversed() {
                let letterRange = match.range(at: 2)
                let letter = nsString.substring(with: letterRange).uppercased()
                let prefixRange = match.range(at: 1)
                let prefix = nsString.substring(with: prefixRange)
                
                let fullRange = match.range
                if let swiftRange = Range(fullRange, in: result) {
                    result.replaceSubrange(swiftRange, with: prefix + letter)
                }
            }
        }
        
        // Common proper tech terms & acronyms
        let acronyms = [
            #"(?i)\bai\b"#: "AI",
            #"(?i)\bapi\b"#: "API",
            #"(?i)\bapis\b"#: "APIs",
            #"(?i)\bui\b"#: "UI",
            #"(?i)\bux\b"#: "UX",
            #"(?i)\bmacos\b"#: "macOS",
            #"(?i)\bios\b"#: "iOS",
            #"(?i)\burl\b"#: "URL",
            #"(?i)\burls\b"#: "URLs",
            #"(?i)\bpdf\b"#: "PDF",
            #"(?i)\bswift\b"#: "Swift",
            #"(?i)\bjson\b"#: "JSON",
            #"(?i)\bceo\b"#: "CEO",
            #"(?i)\bcto\b"#: "CTO"
        ]
        
        for (pattern, replacement) in acronyms {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        
        return result
    }
    
    // MARK: - 8. Terminal Punctuation
    private func applyTerminalPunctuation(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        
        // If already ends in valid punctuation, keep it
        let terminalChars: Set<Character> = [".", "?", "!", ":", ";"]
        if let last = text.last, terminalChars.contains(last) {
            return text
        }
        
        // Detect questions
        let questionStarters = [
            "who", "what", "where", "when", "why", "how",
            "can", "could", "would", "should", "will", "shall",
            "is", "are", "was", "were", "do", "does", "did",
            "am", "may", "might"
        ]
        
        let firstWord = text.components(separatedBy: .whitespaces).first?.lowercased() ?? ""
        if questionStarters.contains(firstWord) {
            return text + "?"
        } else {
            return text + "."
        }
    }
}
