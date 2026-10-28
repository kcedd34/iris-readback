package com.readback.units;

import java.io.InputStream;
import java.math.BigDecimal;
import java.math.MathContext;

import org.fhir.ucum.Decimal;
import org.fhir.ucum.UcumEssenceService;
import org.fhir.ucum.UcumException;

/**
 * Converts a result value to the reference unit of its analyte with the reference UCUM library.
 *
 * <p>Rules (contracts/units-component.md): trim spaces from the units and change nothing else about the
 * spelling (UCUM is case-sensitive); equal units need no conversion; units UCUM reports as comparable are
 * converted by UCUM; a mass concentration against an amount concentration (canonical forms g.m-3 and m-3)
 * goes through the molar mass of the analyte, with UCUM doing the unit arithmetic on both sides; anything
 * else is not convertible. Values are decimals and are never routed through a binary floating-point number.
 * There is no table of conversion factors or of spellings.
 */
public final class UnitConverter {

    public static final String NOT_NEEDED = "not-needed";
    public static final String CONVERTED = "converted";
    public static final String NOT_CONVERTIBLE = "not-convertible";
    /** An unexpected failure of the component itself, not a statement about the unit. */
    public static final String ERROR = "error";

    private static final String MASS_CONCENTRATION = "g.m-3";
    private static final String AMOUNT_CONCENTRATION = "m-3";
    private static final MathContext MC = new MathContext(20);

    /** The answer of one conversion. */
    public static final class Result {
        public final String outcome;
        public final String value;
        public final String unit;
        public final String message;

        Result(String outcome, String value, String unit, String message) {
            this.outcome = outcome;
            this.value = value;
            this.unit = unit;
            this.message = message;
        }
    }

    private final UcumEssenceService ucum;

    public UnitConverter() throws UcumException {
        this(UnitConverter.class.getResourceAsStream("/ucum-essence.xml"));
    }

    public UnitConverter(InputStream essence) throws UcumException {
        this.ucum = new UcumEssenceService(essence);
    }

    /**
     * @param value        a plain decimal number as text
     * @param unit         the unit as received
     * @param referenceUnit the unit of the analyte table
     * @param molarMass    g/mol as text, or null or empty when the analyte has none
     */
    public Result convert(String value, String unit, String referenceUnit, String molarMass) {
        try {
            String source = unit == null ? "" : unit.trim();
            String target = referenceUnit == null ? "" : referenceUnit.trim();
            if (source.isEmpty() || target.isEmpty()) {
                return fail("the unit is empty");
            }
            BigDecimal number;
            try {
                number = new BigDecimal(value == null ? "" : value.trim());
            } catch (NumberFormatException e) {
                return fail("the value is not a decimal number");
            }
            if (source.equals(target)) {
                return new Result(NOT_NEEDED, plain(number), target, "");
            }
            if (ucum.isComparable(source, target)) {
                return new Result(CONVERTED, convertWithUcum(number, source, target), target, "");
            }
            String sourceForm = ucum.getCanonicalUnits(source);
            String targetForm = ucum.getCanonicalUnits(target);
            BigDecimal mass = molarMass == null || molarMass.trim().isEmpty() ? null : new BigDecimal(molarMass.trim());
            if (mass != null && mass.signum() > 0) {
                if (MASS_CONCENTRATION.equals(sourceForm) && AMOUNT_CONCENTRATION.equals(targetForm)) {
                    BigDecimal gramsPerLiter = new BigDecimal(convertWithUcum(number, source, "g/L"));
                    BigDecimal molesPerLiter = gramsPerLiter.divide(mass, MC);
                    return new Result(CONVERTED, convertWithUcum(molesPerLiter, "mol/L", target), target, "");
                }
                if (AMOUNT_CONCENTRATION.equals(sourceForm) && MASS_CONCENTRATION.equals(targetForm)) {
                    BigDecimal molesPerLiter = new BigDecimal(convertWithUcum(number, source, "mol/L"));
                    BigDecimal gramsPerLiter = molesPerLiter.multiply(mass, MC);
                    return new Result(CONVERTED, convertWithUcum(gramsPerLiter, "g/L", target), target, "");
                }
            }
            return fail("cannot convert " + source + " to " + target + ": the units have different dimensions"
                    + (mass == null ? " and no molar mass is known" : ""));
        } catch (UcumException e) {
            return fail(e.getMessage());
        } catch (RuntimeException e) {
            return new Result(ERROR, "", "", "unexpected failure: " + e.getClass().getSimpleName());
        }
    }

    private String convertWithUcum(BigDecimal number, String from, String to) throws UcumException {
        Decimal converted = ucum.convert(new Decimal(plain(number)), from, to);
        return plain(new BigDecimal(converted.asDecimal()));
    }

    private static String plain(BigDecimal number) {
        String text = number.stripTrailingZeros().toPlainString();
        return text.equals("-0") ? "0" : text;
    }

    private static Result fail(String message) {
        return new Result(NOT_CONVERTIBLE, "", "", message);
    }
}
