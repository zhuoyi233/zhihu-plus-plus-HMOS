/**
 * 想法详情的时间与 IP 属地文案（对齐网页「编辑于 2026-10-16 14:11 ・ IP 属地北京」）。
 *
 * 有更新过就写「编辑于」，否则「发布于」；时间精确到分钟，用设备本地时区。
 * IP 属地只有接口给了才拼上，避免凭空出现「IP 属地」四个字。
 */
export function pinMetaText(createdAt: number, updatedAt: number, ipInfo: string): string {
  const edited = updatedAt > createdAt;
  const value = edited ? updatedAt : createdAt;
  const ip = ipInfo.trim();
  if (!(value > 0) || !Number.isFinite(value)) {
    return ip.length > 0 ? `IP 属地${ip}` : '';
  }
  const text = `${edited ? '编辑于' : '发布于'} ${formatPinTime(new Date(value * 1000))}`;
  return ip.length > 0 ? `${text} ・ IP 属地${ip}` : text;
}

function formatPinTime(date: Date): string {
  const pad = (value: number): string => (value < 10 ? `0${value}` : `${value}`);
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ` +
    `${pad(date.getHours())}:${pad(date.getMinutes())}`;
}
