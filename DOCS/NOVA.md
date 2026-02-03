# Nova Language - Comprehensive Guide

Nova is a lightweight, statement-based interpreted language designed specifically for the NewOS kernel. It provides a simple environment for calculations, string manipulation, and system control.

## 1. Variable Assignment (`set`)

Nova uses the `set` keyword to declare or update variables. There are two primary types: `int` for 32-bit signed integers and `string` for text.

### Integer Variables
Integers are stored as 32-bit signed values.
```nova
set int age = 20;
set int next_year = age + 1;
print(next_year); // Output: 21
```

### String Variables
Strings are wrapped in double quotes.
```nova
set string user = "Admin";
set string welcome = "Hello, " + user;
print(welcome); // Output: Hello, Admin
```

### Key Rules for `set`:
- **Naming**: Variable names can be up to 16 characters long.
- **Updating**: If you `set` an existing variable, its value and type will be updated.
- **Auto-casting**: If you assign an integer expression to a `string` variable, it is automatically converted to text.
  ```nova
  set string result = 100 + 50; // result becomes "150"
  ```

---

## 2. Expressions and Operators

Nova evaluates expressions using a **Left-to-Right** approach. Standard mathematical precedence (PEMDAS) is *not* currently implemented, but you can control order using parentheses.

### Arithmetic Operators
- `+` (Addition)
- `-` (Subtraction)
- `*` (Multiplication)
- `/` (Integer division)

### String Operators
- `+` (Concatenation): Joins two strings together.

### Parentheses
Use `(` and `)` to group operations. 
```nova
set int val = 2 * (5 + 5); // 20
```

---

## 3. Built-in Commands

- `print(expression);`: Evaluates the expression and prints result.
- `exit();`: Closes the Nova interpreter and returns to the shell.
- `reboot();`: Immediate system restart.
- `shutdown();`: Immediate system power-off (via ACPI).

---

## 4. Multi-Statement Logic

Nova supports executing multiple statements on a single line by separating them with a semicolon.

**Example:**
```nova
set int a = 5; set int b = 10; print(a + b);
```

---

## 5. Technical Limits & Implementation Details

Nova is optimized for a low-memory kernel environment:
- **Max Variables**: 16 variables total.
- **Max Variable Name**: 16 characters.
- **Max String Length**: 64 characters (internally stored).
- **Execution**: Purely interpreted statement-by-statement.
- **REPL Features**:
    - **Tab Completion**: Autocompletes `set string`, `set int`, `print(`, etc.
    - **History**: Press **Up/Down** to navigate the last 10 commands.
    - **Insert Mode**: Toggleable with the **Insert** key.
