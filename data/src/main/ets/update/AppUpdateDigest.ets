import { hash } from '@kit.CoreFileKit';

/**
 * 下载产物的完整性校验工具。
 *
 * 说明：曾尝试 cryptoFramework.createMd 分块计算，但模拟器（API 23 镜像）上
 * 原生创建失败（"create C obj failed"），故改用文件系统的 hash 接口，
 * 由底层直接流式计算并返回十六进制串（字母为大写，需统一为小写再比对）。
 */
export async function sha256HexOfFile(filePath: string): Promise<string> {
  const digest = await hash.hash(filePath, 'sha256');
  return digest.toLowerCase();
}
