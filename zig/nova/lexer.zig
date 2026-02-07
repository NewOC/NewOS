const util = @import("util.zig");
const common = @import("common.zig");

pub const TokenType = enum {
    // Keywords
    DEF,
    IMPORT,
    IF,
    WHILE,
    ELSE,
    PRINT,
    EXIT,
    SLEEP,
    REBOOT,
    SHUTDOWN,
    SHELL,
    SET,
    INT_KW,
    STRING_KW,

    // Identifiers and Literals
    IDENTIFIER,
    NUMBER,
    STRING,

    // Operators and Symbols
    EQUALS,         // =
    EQUALS_EQUALS,  // ==
    BANG_EQUALS,    // !=
    LESS,           // <
    GREATER,        // >
    PLUS,           // +
    MINUS,          // -
    STAR,           // *
    SLASH,          // /
    L_PAREN,        // (
    R_PAREN,        // )
    L_BRACE,        // {
    R_BRACE,        // }
    COMMA,          // ,
    SEMICOLON,      // ;

    EOF,
    UNKNOWN,
};

pub const Token = struct {
    ttype: TokenType,
    value: []const u8,
    line: u32,
};

pub const Lexer = struct {
    source: []const u8,
    pos: usize,
    line: u32,

    pub fn init(source: []const u8) Lexer {
        return .{
            .source = source,
            .pos = 0,
            .line = 1,
        };
    }

    fn isAtEnd(self: Lexer) bool {
        return self.pos >= self.source.len;
    }

    fn peek(self: Lexer) u8 {
        if (self.isAtEnd()) return 0;
        return self.source[self.pos];
    }

    fn peekNext(self: Lexer) u8 {
        if (self.pos + 1 >= self.source.len) return 0;
        return self.source[self.pos + 1];
    }

    fn advance(self: *Lexer) u8 {
        const char = self.source[self.pos];
        self.pos += 1;
        return char;
    }

    fn match(self: *Lexer, expected: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.source[self.pos] != expected) return false;
        self.pos += 1;
        return true;
    }

    fn skipWhitespace(self: *Lexer) void {
        while (!self.isAtEnd()) {
            const c = self.peek();
            switch (c) {
                ' ', '\r', '\t' => _ = self.advance(),
                '\n' => {
                    self.line += 1;
                    _ = self.advance();
                },
                '/' => {
                    if (self.peekNext() == '/') {
                        // A comment goes until the end of the line.
                        while (self.peek() != '\n' and !self.isAtEnd()) _ = self.advance();
                    } else {
                        return;
                    }
                },
                else => return,
            }
        }
    }

    pub fn tokenize(self: *Lexer) !util.ArrayList(Token) {
        var tokens = util.ArrayList(Token).init();

        while (!self.isAtEnd()) {
            self.skipWhitespace();
            if (self.isAtEnd()) break;

            const start_pos = self.pos;
            const c = self.advance();

            var ttype: TokenType = .UNKNOWN;

            if (isAlpha(c)) {
                ttype = self.identifier(start_pos);
            } else if (isDigit(c)) {
                ttype = self.number();
            } else {
                ttype = switch (c) {
                    '(' => .L_PAREN,
                    ')' => .R_PAREN,
                    '{' => .L_BRACE,
                    '}' => .R_BRACE,
                    ',' => .COMMA,
                    ';' => .SEMICOLON,
                    '+' => .PLUS,
                    '-' => .MINUS,
                    '*' => .STAR,
                    '/' => .SLASH,
                    '=' => if (self.match('=')) .EQUALS_EQUALS else .EQUALS,
                    '!' => if (self.match('=')) .BANG_EQUALS else .UNKNOWN,
                    '<' => .LESS,
                    '>' => .GREATER,
                    '"' => self.string(),
                    else => .UNKNOWN,
                };
            }

            const token = Token{
                .ttype = ttype,
                .value = self.source[start_pos..self.pos],
                .line = self.line,
            };

            // For strings, we might want to strip quotes in the value,
            // but for now let's keep the raw slice.

            if (!tokens.append(token)) return error.OutOfMemory;
        }

        const eof_token = Token{
            .ttype = .EOF,
            .value = "",
            .line = self.line,
        };
        if (!tokens.append(eof_token)) return error.OutOfMemory;

        return tokens;
    }

    fn identifier(self: *Lexer, start_pos: usize) TokenType {
        while (isAlphaNumeric(self.peek())) _ = self.advance();

        const text = self.source[start_pos..self.pos];

        if (common.streq(text, "def")) return .DEF;
        if (common.streq(text, "import")) return .IMPORT;
        if (common.streq(text, "if")) return .IF;
        if (common.streq(text, "while")) return .WHILE;
        if (common.streq(text, "else")) return .ELSE;
        if (common.streq(text, "print")) return .PRINT;
        if (common.streq(text, "exit")) return .EXIT;
        if (common.streq(text, "sleep")) return .SLEEP;
        if (common.streq(text, "reboot")) return .REBOOT;
        if (common.streq(text, "shutdown")) return .SHUTDOWN;
        if (common.streq(text, "shell")) return .SHELL;
        if (common.streq(text, "set")) return .SET;
        if (common.streq(text, "int")) return .INT_KW;
        if (common.streq(text, "string")) return .STRING_KW;

        return .IDENTIFIER;
    }

    fn number(self: *Lexer) TokenType {
        while (isDigit(self.peek())) _ = self.advance();
        return .NUMBER;
    }

    fn string(self: *Lexer) TokenType {
        while (self.peek() != '"' and !self.isAtEnd()) {
            if (self.peek() == '\n') self.line += 1;
            _ = self.advance();
        }

        if (self.isAtEnd()) return .UNKNOWN;

        // The closing ".
        _ = self.advance();
        return .STRING;
    }
};

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isAlphaNumeric(c: u8) bool {
    return isAlpha(c) or isDigit(c);
}
