export function truncateText(value: string, maxLength: number): string {
  if (maxLength <= 0) {
    return '';
  }
  if (value.length <= maxLength) {
    return value;
  }
  let result: string = value.substring(0, maxLength);
  if (result.length > 0) {
    const finalCodeUnit: number = result.charCodeAt(result.length - 1);
    if (finalCodeUnit >= 0xD800 && finalCodeUnit <= 0xDBFF) {
      result = result.substring(0, result.length - 1);
    }
  }
  return result;
}
