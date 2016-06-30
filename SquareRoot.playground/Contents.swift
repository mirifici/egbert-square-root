
// http://home.citycable.ch/pierrefleur/HP35/default.htm

let exponentDigits: UInt8 = 3
let mantissaDigits: UInt8 = 10
let wideMantissaDigits: UInt8 = 11
let totalDigits = exponentDigits + mantissaDigits + 1  // 14

typealias Register = UInt64 // Swift doesn't have a UInt56 so use UInt64 and waste the most-significant 8 bits.

typealias Status = UInt64 // Swift doesn't have a UInt48 so use UInt64 and waste the most-significant 16 bits.

typealias Pointer = UInt8 // Swift doesn't have a UInt4 so use UInt8 and waste the most-significant 4 bits.

var pointer: Pointer = 0

enum FieldSelect {
    case mantissa
    case mantissaAndSign
    case sign
    case exponent
    case exponentSign
    case pointer
    case word
    case wordToPointer
}

func maskForFieldSelect(fieldSelect: FieldSelect) -> UInt64 {
    var mask: UInt64
    switch fieldSelect {
    case .mantissa:
        mask = 0x0ffffffffff000
    case .mantissaAndSign:
        mask = 0xfffffffffff000
    case .sign:
        mask = 0xf0000000000000
    case .exponent:
        mask = 0x00000000000fff
    case .exponentSign:
        mask = 0x00000000000f00
    case .pointer:
        mask = 0xf << UInt64(4 * pointer)
    case .word:
        return 0xffffffffffffff
    case .wordToPointer:
        let digitsToZero = 14 - pointer
        mask = 0xffffffffffffff >> UInt64(4 * digitsToZero)
    }
    precondition(mask & 0xff00000000000000 == 0)
    return mask
}

func shiftNibblesForFieldSelect(fieldSelect: FieldSelect) -> UInt8 {
    var shift: UInt8
    switch fieldSelect {
    case .mantissa:
        shift = exponentDigits
    case .mantissaAndSign:
        shift = exponentDigits
    case .sign:
        shift = exponentDigits + mantissaDigits
    case .exponent:
        shift = 0
    case .exponentSign:
        shift = exponentDigits - 1
    case .pointer:
        shift = pointer
    case .word:
        shift = 0
    case .wordToPointer:
        shift = 0
    }
    return shift
}

func asShiftBits(nibbles: UInt8) -> UInt64 {
    if nibbles > wideMantissaDigits {
        return UInt64(4 * wideMantissaDigits)
    } else {
        return UInt64(4 * nibbles)
    }
}

func readField(register: Register, fieldSelect: FieldSelect) -> UInt64 {
    let shiftNibbles = shiftNibblesForFieldSelect(fieldSelect)
    let mask = maskForFieldSelect(fieldSelect)
    return (register & mask) >> asShiftBits(shiftNibbles)
}

func writeField(register: Register, fieldSelect: FieldSelect, value: UInt64) -> UInt64 {
    let shiftNibbles = shiftNibblesForFieldSelect(fieldSelect)
    let mask = maskForFieldSelect(fieldSelect)
    let maskedRegister = register & ~mask
    return maskedRegister | value << asShiftBits(shiftNibbles)
}

// In a calculator, addition and subtraction of fields are among the core functions implemented by the circuitry.

// In our software calculator, to do addition and subtraction starting with the BCD representation, we convert it to decimal, use Swift's addition and subraction, and then convert the result back to BCD.

// Wide (11 digits) BCD-encoded mantissa is converted to a normal Int64 so we can do addition and subtraction.
func wideBcdMantissaAsInteger(wideBcdMantissa: UInt64) -> Int64 {
    var result: Int64 = 0
    var idx: UInt8 = 0
    var multiplier: Int64 = 1
    while idx < wideMantissaDigits {
        let lastDigit = wideBcdMantissa >> asShiftBits(idx) & 0xf
        result = result + Int64(lastDigit) * multiplier
        multiplier = multiplier * 10; idx = idx + 1
    }
    return result
}

assert(wideBcdMantissaAsInteger(0x12345678901) == 12345678901)

func exponentAsInteger(exponent: UInt64) -> Int64 {
    var result: Int64 = 0
    var idx: UInt8 = 0
    var multiplier: Int64 = 1
    while idx < exponentDigits {
        let lastDigit = exponent >> asShiftBits(idx) & 0xf
        result = result + Int64(lastDigit) * multiplier
        multiplier = multiplier * 10; idx = idx + 1
    }
    return result >= 900 ? result - 1000 : result
}

assert(exponentAsInteger(0x023) == 23)
assert(exponentAsInteger(0x998) == -2)

func subtractWideMantissas(wideMinuend: UInt64, wideSubtrahend: UInt64) -> Int64 {
    let minuend = wideBcdMantissaAsInteger(wideMinuend)
    let subtrahend = wideBcdMantissaAsInteger(wideSubtrahend)
    return minuend - subtrahend
}

assert(subtractWideMantissas(0x456, wideSubtrahend:0x123) == 333)

func addWideMantissas(wideOperand1: UInt64, wideOperand2: UInt64) -> Int64 {
    let operand1 = wideBcdMantissaAsInteger(wideOperand1)
    let operand2 = wideBcdMantissaAsInteger(wideOperand2)
    return operand1 + operand2
}

assert(addWideMantissas(0x123, wideOperand2:0x456) == 579)

// Takes any integer that can be represented with wideMantissaDigits and BCD encodes it.
func asBcdMantissa(value: Int64) -> UInt64 {
    var remainder = value
    var result: UInt64 = 0x0
    var idx: UInt8 = wideMantissaDigits
    var divisor: Int64 = 100000000000
    while idx != 0 {
        idx = idx - 1; divisor = divisor / 10
        let aDigit = remainder / divisor
        remainder = remainder % divisor
        result = result << 4 | UInt64(aDigit)
    }
    return result
}

assert(asBcdMantissa(12345678901) == 0x12345678901)

// Takes any integer that can be represented with exponentDigits and BCD encodes it.
func asBcdExponent(value: Int64) -> UInt64 {
    var remainder = value
    var result: UInt64 = 0x0
    var idx: UInt8 = exponentDigits
    var divisor: Int64 = 1000
    while idx != 0 {
        idx = idx - 1; divisor = divisor / 10
        let aDigit = remainder / divisor
        remainder = remainder % divisor
        result = result << 4 | UInt64(aDigit)
    }
    return result
}

func registerAsHexString(register: Register) -> String {
    var result = "0x"
    var idx: UInt8 = exponentDigits + mantissaDigits + 1
    while idx != 0 {
        idx = idx - 1
        let lastDigit = register >> UInt64(4 * idx) & 0xf
        result = result + String(lastDigit)
    }
    return result
}

assert(registerAsHexString(0x01700000000001) == "0x01700000000001")

func mantissaAsHexString(mantissa: UInt64, wide: Bool) -> String {
    var result = "0x"
    var idx: UInt8 = wide ? wideMantissaDigits : mantissaDigits
    while idx != 0 {
        idx = idx - 1
        let lastDigit = mantissa >> asShiftBits(idx) & 0xf
        result = result + String(lastDigit)
    }
    return result
}

assert(mantissaAsHexString(0x1234567890, wide: false) == "0x1234567890")
assert(mantissaAsHexString(0x12345678901, wide: true) == "0x12345678901")

func divideMantissa(numerator: UInt64, denominator: UInt64) -> UInt64 {
    var numeratorMantissa = numerator
    let denominatorMantissa = denominator
    var quotientMantissa: UInt64 = 0x0
    
    var j: UInt8 = 0
    var count: UInt8 = 0
    
    while j <= mantissaDigits {
        let remainder = subtractWideMantissas(numeratorMantissa, wideSubtrahend: denominatorMantissa)
        if remainder >= 0 {
            numeratorMantissa = asBcdMantissa(remainder)
            count = count + 1
        } else {
            quotientMantissa = quotientMantissa << 4 | UInt64(count)
            numeratorMantissa = numeratorMantissa << 4
            count = 0; j = j + 1
        }
    }
    // We have a wide mantissa (one to many digits). Really, we should round it. However, we'll just right-shift it.
    return quotientMantissa >> asShiftBits(1)
}

assert(mantissaAsHexString(divideMantissa(0x2000000000, denominator: 0x2000000000), wide: false) == "0x1000000000")

func subtractExponents(exponent: UInt64, subtrahendExponent: UInt64) -> UInt64 {
    var result: Int64 = exponentAsInteger(exponent) - exponentAsInteger(subtrahendExponent)
    precondition(result >= -99 && result <= 99)
    if result < 0 {
        result = result + 1000
    }
    return asBcdExponent(result)
}

func divide(numerator: Register, denominator: Register) -> Register {
    // Select the mantissas and divide them.
    var numeratorMantissa: UInt64 = readField(numerator, fieldSelect: .mantissa)
    let denominatorMantissa: UInt64 = readField(denominator, fieldSelect: .mantissa)
    precondition(denominatorMantissa != 0)
    var numeratorExponent: UInt64 = readField(numerator, fieldSelect: .exponent)
    let denominatorExponent: UInt64 = readField(denominator, fieldSelect: .exponent)
    if numeratorMantissa < denominatorMantissa {
        numeratorMantissa = numeratorMantissa << 4
        numeratorExponent = numeratorExponent - 1
    }
    let quotientMantissa = divideMantissa(numeratorMantissa, denominator: denominatorMantissa)
    // Select the exponents and subtract them.
    let quotientExponent = subtractExponents(numeratorExponent, subtrahendExponent: denominatorExponent)
    var quotient: Register = 0x0
    quotient = writeField(quotient, fieldSelect: .mantissa, value: quotientMantissa)
    quotient = writeField(quotient, fieldSelect: .exponent, value: quotientExponent)
    return quotient
}

var sixty: Register = 0x06000000000001
var seventeen: Register = 0x01700000000001  // the HP-35's canonical representation of 17
var five: Register = 0x05000000000000  // the HP-35's canonical representation of 5

// asHexString(divide(seventeen, denominator: five))
// asHexString(divide(sixty, denominator: five))
registerAsHexString(divide(five, denominator: seventeen))

func takeSquareRootMantissa(operand: UInt64) -> UInt64 {
    var remainderMantissa = divideMantissa(operand, denominator: 0x2000000000) << asShiftBits(1) // a way of multiplying by 5
    
    var aMantissa: UInt64 = 0x0
    var j: UInt8 = 0
    var bMinus1: UInt8 = 0
    
    while j < mantissaDigits {
        let firstTermMantissa = (aMantissa << asShiftBits(1)) >> asShiftBits(j) // this is the 10 * a term
        let secondTerm = UInt64(bMinus1) << asShiftBits(1) + 5 // this is the term that is 5, 15, 25, etc. as b increases
        let secondTermMantissa = (secondTerm << asShiftBits(mantissaDigits - 1)) >> asShiftBits(2 * j) // now the second term is aligned
        let decrementMantissa = asBcdMantissa(addWideMantissas(firstTermMantissa, wideOperand2: secondTermMantissa))
        // now try taking decrementMantissa away from remainderMantissa
        let remainder = subtractWideMantissas(remainderMantissa, wideSubtrahend: decrementMantissa)
        if remainder >= 0 {
            remainderMantissa = asBcdMantissa(remainder)
            bMinus1 = bMinus1 + 1
        } else {
            // we have found the jth digit of aMantissa (counting from the most significant) -- it is bMinus1
            aMantissa = aMantissa | UInt64(bMinus1) << asShiftBits(mantissaDigits - 1 - j)
            j = j + 1; bMinus1 = 0
        }
    }
    
    return aMantissa
}

print("\(wideBcdMantissaAsInteger(takeSquareRootMantissa(0x6600000000)))")
