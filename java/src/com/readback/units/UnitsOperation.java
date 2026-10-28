package com.readback.units;

import com.intersystems.enslib.pex.BusinessOperation;

/** PEX business operation that converts a result value to the reference unit of its analyte. */
public class UnitsOperation extends BusinessOperation {
    private UnitConverter converter;

    @Override
    public void OnInit() throws Exception {
        converter = new UnitConverter();
    }

    @Override
    public void OnTearDown() throws Exception {
    }

    @Override
    public Object OnMessage(Object request) throws Exception {
        ConvertRequest in = (ConvertRequest) request;
        ConvertResponse out = new ConvertResponse();
        UnitConverter.Result result;
        try {
            result = converter.convert(in.value, in.unit, in.referenceUnit, in.molarMass);
        } catch (RuntimeException e) {
            out.outcome = UnitConverter.ERROR;
            out.value = "";
            out.unit = "";
            out.message = "unexpected failure: " + e.getClass().getSimpleName();
            return out;
        }
        out.outcome = result.outcome;
        out.value = result.value;
        out.unit = result.unit;
        out.message = result.message;
        return out;
    }
}
