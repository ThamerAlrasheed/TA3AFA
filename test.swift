import Foundation

let code = "000041"
let digits1 = code.filter { $0.isWholeNumber }
let digits2 = code.filter { $0.isNumber }
let digits3 = code.filter { ("0"..."9").contains($0) }
let digits4 = code.filter { $0.isASCII && $0.isNumber }

print("digits1: \(digits1)")
print("digits2: \(digits2)")
print("digits3: \(digits3)")
print("digits4: \(digits4)")
