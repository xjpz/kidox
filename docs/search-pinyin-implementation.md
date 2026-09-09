# 中文拼音搜索实施与验证记录

日期：2026-09-09。依据已审核的 [修改方案](search-pinyin-improvement-plan.md) 实施。本记录区分完整工作区的运行验收与单独搜索提交的验证；没有推送远端。

## 实现结果

- 保留中文、英文名称搜索，加入中文全拼、首字母和连续音节边界匹配。`x / xt / xtsz / xitong / shezhi / sz` 可查找系统设置；`wx / weixin / wei xin` 可查找微信。
- 默认排序按相关度排列，`wx` 的完整缩写命中优先于微信开发者工具的前缀命中；单字母不享受完整缩写加分。多词查询要求所有词命中，分数不会越过名称来源层级。
- 扫描器为本地名称保留语言标识。中文别名支持拼音；其他语言和旧的无来源别名降低优先级、限制短查询，预览不再仅因越南语 `Xem trước` 命中 `x`。
- 使用 Foundation 汉语转写，保留音节信息，纠正已确认的“音乐/音樂”读音，支持 ü 的 v/u 输入。转换失败时仍保留字面搜索。
- Store 持有增量索引，后台生成拼音，名称不变时复用；打开次数、位置变化不会触发重新转写。旧任务按 generation 拒绝，查询结果缓存包含索引 revision，容量上限 64。索引刷新时尽量保持仍然存在的键盘选中项。
- `localizedSearchNames` 是可选字段，旧布局可直接读取；扫描补齐来源。新字段只保存原始名称，不持久化派生拼音。

主要改动为 `PinyinSearchNormalizer`、`ApplicationSearchIndex`、`ApplicationScanner`、`LaunchItem`、`KidoXStore`、语言上下文及 `ContentView` 的索引刷新选择处理。没有新增搜索界面控件。

## 自动化与构建

Release 的 `KidoXRecommendations` 测试 scheme 共 **46 项通过，0 失败**：15 项搜索测试及既有 31 项推荐、页面和偏好测试。搜索测试包含匹配/相对排序、语言来源、旧新数据兼容、改名/语言变化、隐藏/删除、过期和未完成索引任务、真实扫描器读取临时应用资源、转换失败及性能测量。

```sh
xcodebuild -project KidoXApp.xcodeproj -scheme KidoXRecommendations -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData/RecommendationTests \
  -clonedSourcePackagesDirPath DerivedData/SourcePackages -disableAutomaticPackageResolution \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM='' test

KIDOX_SOURCE_PACKAGES="$PWD/DerivedData/SourcePackages" ./script/build_and_run.sh --build-only
```

Release 构建成功。测试结果位于 `DerivedData/RecommendationTests/Logs/Test/Test-KidoXRecommendations-2026.09.09_15-19-10-+0800.xcresult`。测试日志 `/tmp/kidox-search-tests-final.log`，构建日志 `/tmp/kidox-search-build.log`；这些是本机临时证据，可能被后续构建覆盖。

1,000 条包含中文和别名的内存样本，本次 Release 测量：

| 阶段 | 耗时 |
|---|---:|
| 首次索引准备与完整构建 | 98.36 ms |
| 热查询匹配与分数排序 p95，7 种查询各 3 次 | 9.14 ms |
| 1 条名称变更的索引增量更新 | 2.23 ms |

热查询未重新执行拼音转写，p95 达到方案的 10 ms 预算。该测量针对纯索引匹配与分数排序，不代表完整 SwiftUI 帧耗时或大型真实应用库的性能保证。

## 本机界面验证

最终安装产物通过实际窗口操作确认：

- `x` 显示系统设置，排在 DBX、文本编辑之前；预览没有混入。
- `wx` 显示微信、微信开发者工具，微信排第一。
- `xtsz` 仅显示系统设置。

同轮首次实现产物还验证了中文“微信”输入、普通第 3 页搜索后 Escape 恢复来源页，以及从负一页搜索 `jsq`、Return 启动计算器后重新打开仍回到负一页。随后仅调整两处评分边界，最终产物重新执行全部 46 项测试并复查上述三个搜索例子。

中文通过粘贴输入；中文输入法的标记/组合态、连续快速键入与后台刷新恰好交错、所有排序选项的真实窗口操作未逐项单独验收。纯索引过期任务测试不等同于完整 Store/UI 并发交互测试。现有其他排序分支保留，未用相关度覆盖用户选择的排序方式。

## 独立提交范围与复核

按后续“代码提交”要求，仅纳入拼音搜索、语言来源、索引生命周期、键盘选择保护及必要测试基础设施。推荐页、页面记忆、文件夹修复和其他已有修改保留在工作区，未混入搜索提交。新增 `KidoXSearch` scheme 可直接运行搜索测试。上面的 46 项结果与已安装包对应完整工作区，不代表单独搜索提交包含推荐功能。

将 HEAD 与拟提交片段组合到独立临时目录检查，15 项搜索测试全部通过，主 App 的 Release 构建成功。日志分别为 `/tmp/kidox-search-commit-tests.log` 和 `/tmp/kidox-search-commit-build.log`。此检查不替换已安装版本。

## 安装身份与清理

安装位置为 `/Applications/KidoX.app`，版本 `1.4.2 (16)`。版本号没有递增，以下构建摘要用于区分本次产物：

```text
SHA-256: df0a2e390239f1224476fccebbe95b8a9e2539e370d903e68517dc1b7c6f8f53
核验时 PID: 26201
运行路径: /Applications/KidoX.app/Contents/MacOS/KidoX
```

源包与安装包的完整文件清单、权限、符号链接一致，`codesign --verify --deep --strict` 通过，只有一个 KidoX 主进程且启动后持续存活。详见 本机安装核验记录 `Releases/Backups/KidoX-install-20260909-152134.json`（该目录不入库）。PID 是核验时快照，重启后会变化。

最终替换的临时旧包已在界面检查通过后删除，`Releases/Backups` 中剩余 `.app.backup` 数量为 0，仅保留小型审计记录。详见 本机清理记录 `Releases/Backups/KidoX-pinyin-backup-cleanup-20260909-152134.json`（该目录不入库）。

## 数据与既有改动

安装前后只读对比确认：页面 ID、应用集合、可见应用顺序、文件夹关系、隐藏状态及用户改名保持一致。旧扫描流程会压紧隐藏项留下的可见排序间隙，本次观察到部分 `sortIndex` 数值改变，不能将其描述为原始 JSON 完全不变；可见顺序未改变。

没有覆盖或还原用户数据库。测试启动计算器使其次数从 2 增至 3；最终检查另外观察到 OpenDisplay 从 0 增至 1，本轮自动化没有启动该应用，未改回这些实际运行期间的统计。

推荐页 24 项上限、无标题布局、当前进程内记住上次页及搜索来源恢复逻辑保留。安装重启仍按原规则从第一页开始。原有许可证、应用配置、主 App/Helper Info.plist 和 Helper 源文件与实施前摘要一致；文件夹修复未回退。

多音字支持仍以系统转写和已测试词组纠正为范围，不保证所有生僻名称的所有读法。
