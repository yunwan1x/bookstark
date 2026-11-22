//! Data-only computation bridge. Never opens files, network, account state or
//! modifies the supplied Univer snapshot; the caller owns compatibility checks.
use ironcalc_base::{cell::CellValue, types::CellType, Model};
use serde_json::{json, Value};
use std::ffi::{c_char, CStr, CString};
const MAX_INPUT: usize = 5 * 1024 * 1024;

pub fn calculate(source: &[u8]) -> Result<Value, String> {
    if source.len() > MAX_INPUT { return Err("input_limit".into()); }
    let input: Value = serde_json::from_slice(source).map_err(|_| "invalid_json")?;
    let sheets = input["sheets"].as_array().ok_or("invalid_sheets")?;
    if sheets.is_empty() || sheets.len() > 256 { return Err("sheet_limit".into()); }
    let mut model = Model::new_empty("BookStark", "en", "UTC", "en")?;
    let mut formulas = Vec::new();
    let mut ids = std::collections::HashSet::new();
    let mut count = 0;
    for (index, sheet) in sheets.iter().enumerate() {
        let id = sheet["id"].as_str().ok_or("invalid_id")?;
        let name = sheet["name"].as_str().ok_or("invalid_name")?;
        if !ids.insert(id) { return Err("duplicate_id".into()); }
        if index == 0 { model.rename_sheet_by_index(0, name)?; }
        else { model.add_sheet(name)?; }
    }
    for (index, sheet) in sheets.iter().enumerate() {
        let cells = sheet["cells"].as_array().ok_or("invalid_cells")?;
        for cell in cells {
            count += 1;
            if count > 30000 { return Err("cell_limit".into()); }
            let row = cell["r"].as_u64().filter(|r| *r < 1048576).ok_or("invalid_row")? as i32 + 1;
            let col = cell["c"].as_u64().filter(|c| *c < 16384).ok_or("invalid_column")? as i32 + 1;
            let user_input = if let Some(formula) = cell["f"].as_str() {
                if !formula.starts_with('=') || formula.len() > 16384 { return Err("invalid_formula".into()); }
                if formula.contains('[') || formula.contains(']') { return Err("external_or_structured_reference".into()); }
                formulas.push((index as u32, row, col));
                if formulas.len() > 10000 { return Err("formula_limit".into()); }
                formula.to_string()
            } else {
                match &cell["v"] {
                    Value::Null => continue,
                    Value::String(s) => format!("'{s}"),
                    Value::Number(n) => n.to_string(),
                    Value::Bool(b) => if *b { "TRUE".into() } else { "FALSE".into() },
                    _ => return Err("unsupported_value".into()),
                }
            };
            model.set_user_input(index as u32, row, col, user_input)?;
        }
    }
    model.evaluate();
    let mut results = Vec::with_capacity(formulas.len());
    for (sheet, row, col) in formulas {
        let value = match model.get_cell_value_by_index(sheet, row, col)? {
            CellValue::None => Value::Null,
            CellValue::Number(n) if n.is_finite() => json!(n),
            CellValue::Number(_) => return Err("nonfinite_result".into()),
            CellValue::String(s) => json!(s),
            CellValue::Boolean(b) => json!(b),
        };
        let error = model.get_cell_type(sheet, row, col)? == CellType::ErrorValue;
        results.push(json!({"sheet": sheets[sheet as usize]["id"], "r": row-1, "c": col-1, "v": value, "error": error}));
    }
    Ok(json!({"version": 1, "results": results}))
}

#[no_mangle]
pub extern "C" fn bs_alloc_input(length: usize) -> *mut u8 {
    if length == 0 || length > MAX_INPUT { return std::ptr::null_mut(); }
    Box::into_raw(vec![0u8; length].into_boxed_slice()) as *mut u8
}
/// Input pointers/lengths must be the exact pair returned by bs_alloc_input.
#[no_mangle]
pub unsafe extern "C" fn bs_free_input(pointer: *mut u8, length: usize) {
    if !pointer.is_null() && length > 0 && length <= MAX_INPUT {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(pointer, length)));
    }
}
/// The allocation remains owned by the caller for the duration of this call.
#[no_mangle]
pub unsafe extern "C" fn bs_calculate(pointer: *const u8, length: usize) -> *mut c_char {
    let outcome = std::panic::catch_unwind(|| {
        if pointer.is_null() || length == 0 || length > MAX_INPUT { return Err("input_limit".into()); }
        calculate(std::slice::from_raw_parts(pointer, length))
    });
    let result = match outcome {
        Ok(Ok(value)) => json!({"ok": true, "data": value}),
        Ok(Err(_)) => json!({"ok": false, "error": "unsupported_or_invalid_workbook"}),
        Err(_) => json!({"ok": false, "error": "calculation_failed"}),
    };
    CString::new(result.to_string()).unwrap().into_raw()
}
#[no_mangle]
pub unsafe extern "C" fn bs_result_len(pointer: *const c_char) -> usize {
    if pointer.is_null() { return 0; }
    CStr::from_ptr(pointer).to_bytes().len()
}
#[no_mangle]
pub unsafe extern "C" fn bs_free_result(pointer: *mut c_char) {
    if !pointer.is_null() { drop(CString::from_raw(pointer)); }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn run(cells: Value) -> Value {
        calculate(json!({"sheets":[{"id":"s", "name":"预算", "cells":cells}]}).to_string().as_bytes()).unwrap()
    }
    #[test]
    fn dependencies_absolute_references_and_scalars() {
        let v = run(json!([{"r":0,"c":0,"v":1200},{"r":1,"c":0,"v":3600},
            {"r":2,"c":0,"f":"=SUM(A1:A2)"},{"r":2,"c":1,"f":"=$A$3/2"},
            {"r":3,"c":0,"v":"0012"},{"r":3,"c":1,"f":"=LEN(A4)"}]));
        let values: Vec<_> = v["results"].as_array().unwrap().iter().map(|r| r["v"].clone()).collect();
        assert_eq!(values, vec![json!(4800.0),json!(2400.0),json!(4.0)]);
    }
    #[test]
    fn cross_sheet_unicode_and_boolean() {
        let v=calculate(json!({"sheets":[{"id":"a","name":"预算","cells":[{"r":0,"c":0,"v":7},{"r":1,"c":0,"v":true}]},
            {"id":"b","name":"说明","cells":[{"r":0,"c":0,"f":"='预算'!A1*3"},{"r":1,"c":0,"f":"=IF('预算'!A2,1,0)"}]}]}).to_string().as_bytes()).unwrap();
        assert_eq!(v["results"][0]["v"],json!(21.0)); assert_eq!(v["results"][1]["v"],json!(1.0));
    }
    #[test]
    fn errors_cycles_and_unknown_functions_remain_explicit() {
        let v=run(json!([{"r":0,"c":0,"f":"=1/0"},{"r":1,"c":0,"f":"=A2"},{"r":2,"c":0,"f":"=BOOKSTARK_UNKNOWN(1)"}]));
        assert!(v["results"].as_array().unwrap().iter().all(|r| r["error"]==true));
    }
    #[test]
    fn rejects_bounds_and_external_references() {
        for cell in [json!({"r":1048576,"c":0,"v":1}),json!({"r":0,"c":16384,"v":1}),json!({"r":0,"c":0,"f":"=[other]Sheet1!A1"})] {
            assert!(calculate(json!({"sheets":[{"id":"s","name":"S","cells":[cell]}]}).to_string().as_bytes()).is_err());
        }
        assert!(calculate(b"{}").is_err()); assert!(calculate(&vec![b' '; MAX_INPUT+1]).is_err());
    }
}
