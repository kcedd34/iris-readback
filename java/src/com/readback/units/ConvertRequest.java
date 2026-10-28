package com.readback.units;

/** Request of the unit conversion operation. All fields are text; values are plain decimals. */
public class ConvertRequest extends com.intersystems.enslib.pex.Message {
    public String value;
    public String unit;
    public String referenceUnit;
    /** g/mol, or empty when the analyte has none. */
    public String molarMass;
}
