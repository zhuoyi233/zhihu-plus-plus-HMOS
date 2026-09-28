/** 与 pure_live 的下载代理顺序一致；仅对本仓库已发布的未签名 HAP 生成链接。 */
const DOWNLOAD_PROXIES: string[] = [
  'https://cdn.gh-proxy.org/', 'https://edgeone.gh-proxy.org/', 'https://hk.gh-proxy.org/',
  'https://gh.noki.eu.org/', 'https://gh-proxy.com/', 'https://slink.ltd/',
  'https://gh.catmak.name/', 'https://proxy.gitwarp.top/', 'https://github.ednovas.xyz/',
  'https://ghproxy.monkeyray.net/', 'https://fastgit.cc/', 'https://ghfile.geekertao.top/',
  'https://gh-proxy.org/', 'https://ghproxy.net/', 'https://wget.la/',
  'https://git.yylx.win/', 'https://g.blfrp.cn/'
];

export interface AppUpdateDownloadSource {
  label: string;
  url: string;
  resumable: boolean;
  official: boolean;
}

export function updateDownloadSources(assetUrl: string): AppUpdateDownloadSource[] {
  if (!/^https:\/\/github\.com\/zhuoyi233\/zhihu-plus-plus-HMOS\/releases\/download\/HMOSv[0-9.]+\/ZhihuPlusPlus-HMOS-v[0-9.]+-unsigned\.hap$/.test(assetUrl)) {
    return [];
  }
  const sources: AppUpdateDownloadSource[] = [];
  for (let index = 0; index < DOWNLOAD_PROXIES.length; index += 1) {
    sources.push({ label: `下载源 ${index + 1}`, url: DOWNLOAD_PROXIES[index] + assetUrl,
      resumable: index < 12, official: false });
  }
  sources.push({ label: 'GitHub 官方源', url: assetUrl, resumable: true, official: true });
  return sources;
}
