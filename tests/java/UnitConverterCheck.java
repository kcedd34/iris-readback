import java.math.BigDecimal;

import com.readback.units.UnitConverter;

/** Checks of the unit converter against the real UCUM library. Exits non-zero on any failure. */
public class UnitConverterCheck {
    private static int failures = 0;
    private static int checks = 0;

    private static void check(boolean condition, String message) {
        checks++;
        if (!condition) {
            failures++;
            System.out.println("FAIL: " + message);
        }
    }

    private static UnitConverter.Result run(UnitConverter c, String value, String unit, String ref, String molar) {
        return c.convert(value, unit, ref, molar);
    }

    private static boolean near(String actual, String expected, String tolerance) {
        return new BigDecimal(actual).subtract(new BigDecimal(expected)).abs().compareTo(new BigDecimal(tolerance)) < 0;
    }

    public static void main(String[] args) throws Exception {
        UnitConverter c = new UnitConverter();
        UnitConverter.Result r;

        r = run(c, "5.4", "mmol/L", "mmol/L", null);
        check(r.outcome.equals("not-needed") && r.value.equals("5.4") && r.unit.equals("mmol/L"), "same unit is not-needed: " + r.outcome + " " + r.value);

        r = run(c, "126", "mg/dL", "g/L", null);
        check(r.outcome.equals("converted") && r.value.equals("1.26"), "126 mg/dL to g/L is 1.26: " + r.outcome + " " + r.value + " " + r.message);

        r = run(c, "5.4", "mmol/L", "umol/L", null);
        check(r.outcome.equals("converted") && r.value.equals("5400"), "5.4 mmol/L to umol/L is exactly 5400: " + r.value);

        r = run(c, "12.4", "g/dL", "g/L", null);
        check(r.outcome.equals("converted") && r.value.equals("124"), "12.4 g/dL to g/L is 124: " + r.value);

        // Glucose: mass concentration to amount concentration through the molar mass, computed here with BigDecimal.
        BigDecimal expected = new BigDecimal("1.26").divide(new BigDecimal("180.156"), new java.math.MathContext(30)).multiply(new BigDecimal("1000"));
        r = run(c, "126", "mg/dL", "mmol/L", "180.156");
        check(r.outcome.equals("converted") && near(r.value, expected.toPlainString(), "0.00000001"), "126 mg/dL to mmol/L with the molar mass: " + r.outcome + " " + r.value + " expected " + expected);

        r = run(c, "7", "mmol/L", "mg/dL", "180.156");
        BigDecimal back = new BigDecimal("7").multiply(new BigDecimal("180.156")).divide(new BigDecimal("10"));
        check(r.outcome.equals("converted") && near(r.value, back.toPlainString(), "0.0001"), "7 mmol/L to mg/dL with the molar mass is about 126.1: " + r.value);

        r = run(c, "126", "mg/dL", "mmol/L", null);
        check(r.outcome.equals("not-convertible") && !r.message.isEmpty(), "mass to amount without a molar mass is not convertible: " + r.outcome);
        r = run(c, "126", "mg/dL", "mmol/L", "");
        check(r.outcome.equals("not-convertible"), "an empty molar mass is the same as none");

        for (String bad : new String[] {"foo", "mEq/L", "MMOL/L", "mmol / L", ""}) {
            r = run(c, "6.9", bad, "mmol/L", null);
            check(r.outcome.equals("not-convertible") && r.value.isEmpty() && r.unit.isEmpty(), "unit '" + bad + "' is not convertible: " + r.outcome);
        }

        r = run(c, "6.9", "  mmol/L  ", "mmol/L", null);
        check(r.outcome.equals("not-needed"), "surrounding spaces are trimmed: " + r.outcome);
        r = run(c, "5.4", " mmol/L", " umol/L ", null);
        check(r.outcome.equals("converted") && r.value.equals("5400"), "spaces are trimmed on both units: " + r.value);

        r = run(c, "six", "mmol/L", "mmol/L", null);
        check(r.outcome.equals("not-convertible"), "a value that is not a decimal is not convertible");
        r = run(c, "", "mmol/L", "mmol/L", null);
        check(r.outcome.equals("not-convertible"), "an empty value is not convertible");

        r = run(c, "6.9", "mmol/L", "mL", "180.156");
        check(r.outcome.equals("not-convertible"), "units of other dimensions stay not convertible even with a molar mass: " + r.outcome);
        r = run(c, "6.9", "mmol/L", "g/dL", "180.156");
        check(r.outcome.equals("converted"), "an amount concentration to a mass concentration is valid with a molar mass: " + r.outcome);

        UnitConverter.Result a = run(c, "126", "mg/dL", "mmol/L", "180.156");
        UnitConverter.Result b = run(c, "126", "mg/dL", "mmol/L", "180.156");
        check(a.value.equals(b.value) && a.outcome.equals(b.outcome), "the same input gives the same output");

        // No double: a value with more digits than a double keeps them.
        r = run(c, "0.1234567890123456789", "mmol/L", "umol/L", null);
        check(r.outcome.equals("converted") && r.value.startsWith("123.4567890123456789"), "digits beyond a double are kept: " + r.value);

        // The result path of the converter source has no floating-point arithmetic.
        String source = new String(java.nio.file.Files.readAllBytes(java.nio.file.Paths.get(args.length > 0 ? args[0] : "java/src/com/readback/units/UnitConverter.java")));
        check(!source.contains("double ") && !source.contains("Double.") && !source.contains("float "), "the converter source uses no floating-point types");

        System.out.println(checks + " checks, " + failures + " failures");
        System.exit(failures == 0 ? 0 : 1);
    }
}
