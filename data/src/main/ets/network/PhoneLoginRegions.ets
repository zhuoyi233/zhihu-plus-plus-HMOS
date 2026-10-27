/**
 * 知乎官网验证码登录页的国家/地区与拨号前缀白名单。
 *
 * 数据来源：2026-10-27 展开 https://www.zhihu.com/signin 的“验证码登录”地区下拉框，
 * 按页面顺序照录 182 项（名称与展示前缀均沿用官网原文，不做国际标准码换算）。
 *
 * 注意：
 * 1. 共 180 个不同拨号前缀：美国/加拿大同用 +1，俄罗斯/哈萨克斯坦同用 +7，
 *    因此地区数据与选中状态都不能以区号作为唯一键，必须用 id。
 * 2. 巴哈马 +1242、关岛 +1671 等是官网展示的拨号前缀（含共享号码计划地区前缀），
 *    不能按“国家呼叫码最多三位”截断。
 * 3. 官网顺序并非严格按区号排序（末尾是塞尔维亚 +381、毛里塔尼亚 +222），
 *    空查询一律按官网原顺序展示。
 * 4. 这份白名单只证明官网登录页提供这些选项，不代表 Android 登录接口对所有地区
 *    都能发码成功，真实联调属于功能验收门槛。
 */

/** 单个国家/地区条目。 */
export interface PhoneLoginRegion {
  /** 稳定地区标识（通常为 ISO 3166-1 alpha-2；用于选中状态与请求参数，不随名称变化）。 */
  readonly id: string;
  /** 官网展示名称（照录）。 */
  readonly displayName: string;
  /** 拨号前缀，不含 “+”。 */
  readonly dialPrefix: string;
  /** 号码格式化使用地区标识（默认与 id 相同，特殊地区可覆盖）。 */
  readonly formatRegion: string;
  /** 检索别名（除名称与 id 之外可命中的关键词，如英文名）。 */
  readonly searchAliases: Array<string>;
  /** 官网顺序，从 1 开始。 */
  readonly order: number;
}

export const DEFAULT_PHONE_LOGIN_REGION_ID: string = 'CN';

/** [id, 名称, 拨号前缀, 检索别名（以 | 分隔）, 可选格式化地区覆盖] */
const REGION_ROWS: Array<Array<string>> = [
  ['CN', '中国', '86', '中国大陆|中国内地|China|PRC'],
  ['US', '美国', '1', 'United States|USA|America'],
  ['JP', '日本', '81', 'Japan'],
  ['HK', '中国香港', '852', '香港|Hong Kong'],
  ['MO', '中国澳门', '853', '澳门|Macau|Macao'],
  ['TW', '中国台湾', '886', '台湾|Taiwan'],
  ['MY', '马来西亚', '60', 'Malaysia'],
  ['AU', '澳大利亚', '61', '澳洲|Australia'],
  ['CA', '加拿大', '1', 'Canada'],
  ['GB', '英国', '44', 'United Kingdom|UK|Britain|England'],
  ['SG', '新加坡', '65', 'Singapore'],
  ['DE', '德国', '49', 'Germany'],
  ['RU', '俄罗斯', '7', 'Russia'],
  ['EG', '埃及', '20', 'Egypt'],
  ['ZA', '南非', '27', 'South Africa'],
  ['GR', '希腊', '30', 'Greece'],
  ['NL', '荷兰', '31', 'Netherlands'],
  ['BE', '比利时', '32', 'Belgium'],
  ['FR', '法国', '33', 'France'],
  ['ES', '西班牙', '34', 'Spain'],
  ['HU', '匈牙利', '36', 'Hungary'],
  ['IT', '意大利', '39', 'Italy'],
  ['RO', '罗马尼亚', '40', 'Romania'],
  ['CH', '瑞士', '41', 'Switzerland'],
  ['AT', '奥地利', '43', 'Austria'],
  ['DK', '丹麦', '45', 'Denmark'],
  ['SE', '瑞典', '46', 'Sweden'],
  ['NO', '挪威', '47', 'Norway'],
  ['PL', '波兰', '48', 'Poland'],
  ['PE', '秘鲁', '51', 'Peru'],
  ['MX', '墨西哥', '52', 'Mexico'],
  ['CU', '古巴', '53', 'Cuba'],
  ['AR', '阿根廷', '54', 'Argentina'],
  ['BR', '巴西', '55', 'Brazil'],
  ['CL', '智利', '56', 'Chile'],
  ['CO', '哥伦比亚', '57', 'Colombia'],
  ['VE', '委内瑞拉', '58', 'Venezuela'],
  ['ID', '印度尼西亚', '62', '印尼|Indonesia'],
  ['PH', '菲律宾', '63', 'Philippines'],
  ['NZ', '新西兰', '64', 'New Zealand'],
  ['TH', '泰国', '66', 'Thailand'],
  ['KZ', '哈萨克斯坦', '7', 'Kazakhstan'],
  ['KR', '韩国', '82', 'South Korea|Korea'],
  ['VN', '越南', '84', 'Vietnam'],
  ['TR', '土耳其', '90', 'Turkey'],
  ['IN', '印度', '91', 'India'],
  ['PK', '巴基斯坦', '92', 'Pakistan'],
  ['AF', '阿富汗', '93', 'Afghanistan'],
  ['LK', '斯里兰卡', '94', 'Sri Lanka'],
  ['MM', '缅甸', '95', 'Myanmar'],
  ['IR', '伊朗', '98', 'Iran'],
  ['MA', '摩洛哥', '212', 'Morocco'],
  ['DZ', '阿尔及利亚', '213', 'Algeria'],
  ['TN', '突尼斯', '216', 'Tunisia'],
  ['LY', '利比亚', '218', 'Libya'],
  ['GM', '冈比亚', '220', 'Gambia'],
  ['SN', '塞内加尔', '221', 'Senegal'],
  ['ML', '马里', '223', 'Mali'],
  ['GN', '几内亚', '224', 'Guinea'],
  ['CI', '科特迪瓦', '225', 'Ivory Coast'],
  ['BF', '布基纳法索', '226', 'Burkina Faso'],
  ['NE', '尼日尔', '227', 'Niger'],
  ['TG', '多哥', '228', 'Togo'],
  ['BJ', '贝宁', '229', 'Benin'],
  ['MU', '毛里求斯', '230', 'Mauritius'],
  ['LR', '利比里亚', '231', 'Liberia'],
  ['SL', '塞拉利昂', '232', 'Sierra Leone'],
  ['GH', '加纳', '233', 'Ghana'],
  ['NG', '尼日利亚', '234', 'Nigeria'],
  ['TD', '乍得', '235', 'Chad'],
  ['CF', '中非共和国', '236', 'Central African Republic'],
  ['CM', '喀麦隆', '237', 'Cameroon'],
  ['ST', '圣多美和普林西比', '239', 'Sao Tome and Principe'],
  ['GA', '加蓬', '241', 'Gabon'],
  ['CD', '刚果民主共和国', '243', '刚果金|DR Congo'],
  ['AO', '安哥拉', '244', 'Angola'],
  ['AC', '阿森松岛', '247', 'Ascension Island'],
  ['SC', '塞舌尔', '248', 'Seychelles'],
  ['SD', '苏丹', '249', 'Sudan'],
  ['ET', '埃塞俄比亚', '251', 'Ethiopia'],
  ['SO', '索马里', '252', 'Somalia'],
  ['DJ', '吉布提', '253', 'Djibouti'],
  ['KE', '肯尼亚', '254', 'Kenya'],
  ['TZ', '坦桑尼亚', '255', 'Tanzania'],
  ['UG', '乌干达', '256', 'Uganda'],
  ['BI', '布隆迪', '257', 'Burundi'],
  ['MZ', '莫桑比克', '258', 'Mozambique'],
  ['ZM', '赞比亚', '260', 'Zambia'],
  ['MG', '马达加斯加', '261', 'Madagascar'],
  ['ZW', '津巴布韦', '263', 'Zimbabwe'],
  ['NA', '纳米比亚', '264', 'Namibia'],
  ['MW', '马拉维', '265', 'Malawi'],
  ['LS', '莱索托', '266', 'Lesotho'],
  ['BW', '博茨瓦纳', '267', 'Botswana'],
  ['SZ', '斯威士兰', '268', 'Eswatini|Swaziland'],
  ['GI', '直布罗陀', '350', 'Gibraltar'],
  ['PT', '葡萄牙', '351', 'Portugal'],
  ['LU', '卢森堡', '352', 'Luxembourg'],
  ['IE', '爱尔兰', '353', 'Ireland'],
  ['IS', '冰岛', '354', 'Iceland'],
  ['AL', '阿尔巴尼亚', '355', 'Albania'],
  ['MT', '马耳他', '356', 'Malta'],
  ['CY', '塞浦路斯', '357', 'Cyprus'],
  ['FI', '芬兰', '358', 'Finland'],
  ['BG', '保加利亚', '359', 'Bulgaria'],
  ['LT', '立陶宛', '370', 'Lithuania'],
  ['LV', '拉脱维亚', '371', 'Latvia'],
  ['EE', '爱沙尼亚', '372', 'Estonia'],
  ['MD', '摩尔多瓦', '373', 'Moldova'],
  ['AM', '亚美尼亚', '374', 'Armenia'],
  ['BY', '白俄罗斯', '375', 'Belarus'],
  ['AD', '安道尔共和国', '376', 'Andorra'],
  ['MC', '摩纳哥', '377', 'Monaco'],
  ['SM', '圣马力诺', '378', 'San Marino'],
  ['UA', '乌克兰', '380', 'Ukraine'],
  ['SI', '斯洛文尼亚', '386', 'Slovenia'],
  ['CZ', '捷克', '420', 'Czech'],
  ['SK', '斯洛伐克', '421', 'Slovakia'],
  ['LI', '列支敦士登', '423', 'Liechtenstein'],
  ['BZ', '伯利兹', '501', 'Belize'],
  ['GT', '瓜地马拉', '502', '危地马拉|Guatemala'],
  ['SV', '萨尔瓦多', '503', 'El Salvador'],
  ['HN', '洪都拉斯', '504', 'Honduras'],
  ['NI', '尼加拉瓜', '505', 'Nicaragua'],
  ['CR', '哥斯达黎加', '506', 'Costa Rica'],
  ['PA', '巴拿马', '507', 'Panama'],
  ['HT', '海地', '509', 'Haiti'],
  ['BO', '玻利维亚', '591', 'Bolivia'],
  ['GY', '圭亚那', '592', 'Guyana'],
  ['EC', '厄瓜多尔', '593', 'Ecuador'],
  ['GF', '法属圭亚那', '594', 'French Guiana'],
  ['PY', '巴拉圭', '595', 'Paraguay'],
  ['MQ', '马提尼克', '596', 'Martinique'],
  ['SR', '苏里南', '597', 'Suriname'],
  ['UY', '乌拉圭', '598', 'Uruguay'],
  ['BN', '文莱', '673', 'Brunei'],
  ['PG', '巴布亚新几内亚', '675', 'Papua New Guinea'],
  ['TO', '汤加', '676', 'Tonga'],
  ['SB', '所罗门群岛', '677', 'Solomon Islands'],
  ['FJ', '斐济', '679', 'Fiji'],
  ['CK', '库克群岛', '682', 'Cook Islands'],
  ['PF', '法属波利尼西亚', '689', 'French Polynesia'],
  ['KH', '柬埔寨', '855', 'Cambodia'],
  ['LA', '老挝', '856', 'Laos'],
  ['BD', '孟加拉国', '880', 'Bangladesh'],
  ['MV', '马尔代夫', '960', 'Maldives'],
  ['LB', '黎巴嫩', '961', 'Lebanon'],
  ['JO', '约旦', '962', 'Jordan'],
  ['SY', '叙利亚', '963', 'Syria'],
  ['IQ', '伊拉克', '964', 'Iraq'],
  ['KW', '科威特', '965', 'Kuwait'],
  ['SA', '沙特阿拉伯', '966', '沙特|Saudi Arabia'],
  ['YE', '也门', '967', 'Yemen'],
  ['OM', '阿曼', '968', 'Oman'],
  ['AE', '阿拉伯联合酋长国', '971', '阿联酋|UAE'],
  ['IL', '以色列', '972', 'Israel'],
  ['BH', '巴林', '973', 'Bahrain'],
  ['QA', '卡塔尔', '974', 'Qatar'],
  ['MN', '蒙古', '976', 'Mongolia'],
  ['NP', '尼泊尔', '977', 'Nepal'],
  ['TJ', '塔吉克斯坦', '992', 'Tajikistan'],
  ['TM', '土库曼斯坦', '993', 'Turkmenistan'],
  ['AZ', '阿塞拜疆', '994', 'Azerbaijan'],
  ['GE', '格鲁吉亚', '995', 'Georgia'],
  ['KG', '吉尔吉斯斯坦', '996', 'Kyrgyzstan'],
  ['UZ', '乌兹别克斯坦', '998', 'Uzbekistan'],
  ['BS', '巴哈马', '1242', 'Bahamas'],
  ['BB', '巴巴多斯', '1246', 'Barbados'],
  ['AI', '安圭拉岛', '1264', 'Anguilla'],
  ['AG', '安提瓜和巴布达', '1268', 'Antigua and Barbuda'],
  ['KY', '开曼群岛', '1345', 'Cayman Islands'],
  ['BM', '百慕大群岛', '1441', 'Bermuda'],
  ['GD', '格林纳达', '1473', 'Grenada'],
  ['MS', '蒙特塞拉特岛', '1664', 'Montserrat'],
  ['GU', '关岛', '1671', 'Guam'],
  ['LC', '圣露西亚', '1758', 'Saint Lucia'],
  ['PR', '波多黎各', '1787', 'Puerto Rico'],
  ['DO', '多明尼加共和国', '1809', '多米尼加|Dominican Republic'],
  ['TT', '特立尼达和多巴哥', '1868', 'Trinidad and Tobago'],
  ['JM', '牙买加', '1876', 'Jamaica'],
  ['RS', '塞尔维亚共和国', '381', '塞尔维亚|Serbia'],
  ['MR', '毛里塔尼亚', '222', 'Mauritania']
];

function buildRegions(): Array<PhoneLoginRegion> {
  const regions: Array<PhoneLoginRegion> = [];
  for (let index = 0; index < REGION_ROWS.length; index += 1) {
    const row: Array<string> = REGION_ROWS[index];
    const aliases: Array<string> = row.length > 3 && row[3].length > 0 ? row[3].split('|') : [];
    const formatRegion: string = row.length > 4 && row[4].length > 0 ? row[4] : row[0];
    const region: PhoneLoginRegion = {
      id: row[0],
      displayName: row[1],
      dialPrefix: row[2],
      formatRegion: formatRegion,
      searchAliases: aliases,
      order: index + 1
    };
    regions.push(region);
  }
  return regions;
}

/** 官网白名单，按官网顺序排列。 */
export const PHONE_LOGIN_REGIONS: Array<PhoneLoginRegion> = buildRegions();

function buildRegionIndex(): Map<string, PhoneLoginRegion> {
  const index: Map<string, PhoneLoginRegion> = new Map<string, PhoneLoginRegion>();
  PHONE_LOGIN_REGIONS.forEach((region: PhoneLoginRegion): void => {
    index.set(region.id, region);
  });
  return index;
}

/** 拨号前缀按长度降序去重，用于“更长的白名单前缀优先识别”。 */
function buildPrefixesByLength(): Array<string> {
  const seen: Set<string> = new Set<string>();
  const prefixes: Array<string> = [];
  PHONE_LOGIN_REGIONS.forEach((region: PhoneLoginRegion): void => {
    if (!seen.has(region.dialPrefix)) {
      seen.add(region.dialPrefix);
      prefixes.push(region.dialPrefix);
    }
  });
  prefixes.sort((left: string, right: string): number => right.length - left.length);
  return prefixes;
}

const REGIONS_BY_ID: Map<string, PhoneLoginRegion> = buildRegionIndex();
const PREFIXES_BY_LENGTH: Array<string> = buildPrefixesByLength();

/** 默认地区（中国 +86）。 */
export function defaultPhoneLoginRegion(): PhoneLoginRegion {
  const region = REGIONS_BY_ID.get(DEFAULT_PHONE_LOGIN_REGION_ID);
  if (region === undefined) {
    return PHONE_LOGIN_REGIONS[0];
  }
  return region;
}

/** 按 id 查找地区；未命中返回 undefined（调用方决定回退策略）。 */
export function findPhoneLoginRegion(id: string): PhoneLoginRegion | undefined {
  return REGIONS_BY_ID.get(id);
}

/** 展示用区号，如 “+86”。 */
export function regionDialText(region: PhoneLoginRegion): string {
  return `+${region.dialPrefix}`;
}

/** 入口按钮文案，如 “中国 +86”。 */
export function regionEntryLabel(region: PhoneLoginRegion): string {
  return `${region.displayName} ${regionDialText(region)}`;
}

/**
 * 返回与给定数字（不含 “+”）共享最长白名单前缀的全部地区。
 *
 * 例如 “14165551234” → 最长命中 “1” → 美国、加拿大；“12425551234” → 最长命中 “1242” → 巴哈马。
 * 调用方据此判断用户粘贴的完整号码是否属于当前所选地区，避免仅凭短前缀推断具体地区。
 */
export function regionsSharingLongestPrefix(digits: string): Array<PhoneLoginRegion> {
  const matched: Array<PhoneLoginRegion> = [];
  if (digits.length === 0) {
    return matched;
  }
  for (let index = 0; index < PREFIXES_BY_LENGTH.length; index += 1) {
    const prefix: string = PREFIXES_BY_LENGTH[index];
    if (!digits.startsWith(prefix)) {
      continue;
    }
    PHONE_LOGIN_REGIONS.forEach((region: PhoneLoginRegion): void => {
      if (region.dialPrefix === prefix) {
        matched.push(region);
      }
    });
    return matched;
  }
  return matched;
}

function copyRegions(source: Array<PhoneLoginRegion>): Array<PhoneLoginRegion> {
  const result: Array<PhoneLoginRegion> = [];
  source.forEach((region: PhoneLoginRegion): void => {
    result.push(region);
  });
  return result;
}

/**
 * 检索国家/地区。空查询按官网原顺序全量返回；
 * 纯数字（含前缀 “+” 的写法）按拨号前缀前缀匹配，因此搜索 “1” 会同时命中美国、加拿大、
 * 巴哈马等多项；其余按名称、地区标识与别名匹配。
 */
export function matchPhoneLoginRegions(query: string): Array<PhoneLoginRegion> {
  const trimmed: string = query.trim();
  if (trimmed.length === 0) {
    return copyRegions(PHONE_LOGIN_REGIONS);
  }
  const digitQuery: string = trimmed.startsWith('+') ? trimmed.substring(1) : trimmed;
  const matched: Array<PhoneLoginRegion> = [];
  if (/^\d+$/.test(digitQuery)) {
    PHONE_LOGIN_REGIONS.forEach((region: PhoneLoginRegion): void => {
      if (region.dialPrefix.startsWith(digitQuery)) {
        matched.push(region);
      }
    });
    return matched;
  }
  const lower: string = trimmed.toLowerCase();
  PHONE_LOGIN_REGIONS.forEach((region: PhoneLoginRegion): void => {
    if (region.displayName.toLowerCase().includes(lower) ||
      region.id.toLowerCase().includes(lower) ||
      aliasMatched(region, lower)) {
      matched.push(region);
    }
  });
  return matched;
}

function aliasMatched(region: PhoneLoginRegion, lowerQuery: string): boolean {
  let hit: boolean = false;
  region.searchAliases.forEach((alias: string): void => {
    if (alias.toLowerCase().includes(lowerQuery)) {
      hit = true;
    }
  });
  return hit;
}
