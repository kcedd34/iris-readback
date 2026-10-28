package com.readback.units;

/** Answer of the unit conversion operation. See contracts/units-component.md. */
public class ConvertResponse extends com.intersystems.enslib.pex.Message {
    /** converted, not-needed, not-convertible or error. */
    public String outcome;
    public String value;
    public String unit;
    public String message;
}
