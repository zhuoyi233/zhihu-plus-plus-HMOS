# P1 工程模块拆分验证

## 结论

2026-08-11 已将 HarmonyOS 工程从单一 `entry` 模块拆为一个 HAP 与三个真实 HAR。三个 HAR 均包含由 P0/P1 迁入的生产代码，通过根 `Index.ets` 暴露公共 API，不是空壳模块，也没有保留 entry 内的重复实现。

```text
entry (HAP)
  ├── core (HAR)
  ├── data (HAR) ──> core (HAR)
  └── reader (HAR) ──> core (HAR)
```

依赖图不存在回边：`core` 不依赖其他业务模块，`data` 与 `reader` 只依赖 `core`，`entry` 作为组合根依赖三个 HAR。data 复用 core 的有界名义 JSON AST，以同一套运行时边界校验外部响应和导航参数。

## 模块职责

| 模块 | 类型 | 生产源码数 | 职责 |
| --- | --- | ---: | --- |
| `entry` | HAP | 12 | UIAbility、页面、Scan Kit/file fixture、后台任务执行器与资源 |
| `core` | HAR | 8 | API 兼容判断、导航、启动图、安全日志、二维码与后台任务纯策略 |
| `data` | HAR | 18 | DomainModel、decoder、Repository 契约、HTTP、签名、Cookie/加密会话、RDB |
| `reader` | HAR | 5 | 正文解析、列表数据源、图片组件与公式下载/解码 |

`BackgroundTaskProbe`、`P0WorkSchedulerExtensionAbility`、`QrScanFixture` 和全部页面继续留在 `entry`，因为它们直接承担平台执行或界面职责。`BackgroundWorkPolicy` 与 `QrLoginScanPolicy` 不依赖平台执行上下文，归入 `core`。

## 构建与包解析

- 根 `build-profile.json5` 注册 `entry/core/data/reader` 四个模块，产品继续固定 target/compatible API 24，并保留 `useNormalizedOHMUrl`。
- 三个库的 `module.json5` 均声明 `type: har`，`hvigorfile.ts` 均使用 `harTasks`。
- ohpm 包名与依赖 alias 完全一致：`core`、`data`、`reader`。
- `entry/oh-package.json5` 使用 `file:../core`、`file:../data`、`file:../reader`；`data` 与 `reader` 使用 `core: file:../core`。
- 主代码与 Hypium 测试都从 `core`、`data`、`reader` 根包导入，不跨模块引用 `src/main/ets` 深路径。
- `ohpm install` 成功生成模块锁文件并解析本地依赖。

`reader` 打包时会提示 HAR 含本地 file 依赖。当前三个 HAR 是同仓库内部模块，并不作为独立 ohpm 包发布；应用构建会同时解析 `reader` 与 `core`。若未来单独发布 reader HAR，应将 core 发布为版本化 ohpm 依赖后再消除此提示。

## 资源与权限边界

颜色、间距、字符串和 rawfile fixtures 保留在 `entry`，避免本轮同时改变资源命名空间与 fixture 打包位置。reader HAR 不直接查询 entry 资源：`ReaderImageBlock` 接受 `ResourceColor` 参数，entry 页面传入当前主题的 `secondary_text`，因此深浅色行为保留且没有资源反向依赖。

INTERNET 权限仍由最终 HAP 的 `entry/src/main/module.json5` 声明。data/reader 单独编译 HAR 时会提示网络 API 权限，但最终应用清单已经具备权限；不在每个内部 HAR 重复声明权限。

Hvigor 会在各模块根目录生成随构建模式变化的 `BuildProfile.ets`，已通过 `.gitignore` 排除；模块源码不依赖该生成文件。

## 验证记录

执行 DevEco Studio 6.1.1 自带 ohpm：

```powershell
& 'C:\Users\zhuoyi\App\DevEco Studio\tools\ohpm\bin\ohpm.bat' install
```

结果：`install completed`。

执行 API 24 四模块 Debug 构建：

```powershell
devecocli build --modules entry core data reader --build-mode debug
```

结果：`BUILD SUCCESSFUL in 8 s 304 ms`。产物包括：

- `core.har`：25,152 bytes；
- `data.har`：50,380 bytes；
- `reader.har`：25,439 bytes；
- `entry-default-unsigned.hap`：569,701 bytes。

执行完整 Hypium：

```powershell
$env:DEVECO_SDK_HOME='C:\Users\zhuoyi\App\DevEco Studio\sdk'
& 'C:\Users\zhuoyi\App\DevEco Studio\tools\node\node.exe' `
  'C:\Users\zhuoyi\App\DevEco Studio\tools\hvigor\bin\hvigorw.js' `
  test --mode module `
  -p 'module=entry@default' `
  -p 'product=default' `
  -p 'buildMode=debug'
```

Hvigor 结果为 `BUILD SUCCESSFUL in 10 s 31 ms`。同时核对原始 `test_result.txt`，结果为：

```text
Tests run: 62, Failure: 0, Error: 0, Pass: 62, Ignore: 0
```

## 非目标检查

三个 HAR 的源码和包清单未发现 ONNX、TensorFlow、MindSpore、embedding、tokenizer 或 inference 依赖与实现。本轮没有迁移 Android full 版本的端侧 AI、模型文件或本地推理能力。
