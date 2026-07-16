# 第三方数据与许可说明

夜幕验物是非官方社区工具，不隶属于 FromSoftware、Bandai Namco Entertainment 或原参考网站。游戏名称与游戏内简体中文效果文本的权利归其各自权利方所有。

## go-webview2（jchv/go-webview2）

- 项目：https://github.com/jchv/go-webview2
- 用途：WebView2 运行时的纯 Go COM 绑定（`pkg/edge`、`webviewloader`）；
  本项目的 `window.go` 与 `internal/w32` 在其 MIT 代码基础上修改
  （文件头保留了来源与修改说明）
- 许可：MIT License（Copyright (c) 2020 John Chadwick, some portions Copyright (c) 2017 Serge Zaitsev），全文见附录 A.1

## go-winloader（jchv/go-winloader）

- 项目：https://github.com/jchv/go-winloader
- 用途：go-webview2 的 `webviewloader` 借其在内存中加载 WebView2Loader
- 许可：ISC License（Copyright © 2021 John Chadwick），全文见附录 A.4

## Microsoft Edge WebView2 SDK（WebView2Loader）

- 项目：https://www.nuget.org/packages/Microsoft.Web.WebView2
- 用途：go-webview2 内嵌的 WebView2Loader，用于定位并加载系统 WebView2 运行时
- 许可：3-Clause BSD License（Copyright (C) Microsoft Corporation），全文见附录 A.3

页面渲染由 Windows 系统组件 Microsoft Edge WebView2 Runtime 完成，该运行时随系统分发，不包含在本程序内。

## zenity（ncruces/zenity）

- 项目：https://github.com/ncruces/zenity
- 用途：Windows 原生文件打开 / 保存对话框（IFileDialog）
- 许可：MIT License（Copyright (c) 2024 Nuno Cruces），全文见附录 A.1

## golang.org/x/sys

- 项目：https://golang.org/x/sys
- 用途：Windows 系统调用绑定
- 许可：BSD-3-Clause License（Copyright 2009 The Go Authors），全文见附录 A.2

## golang.org/x/image

- 项目：https://golang.org/x/image
- 用途：经 zenity 间接引入的颜色名称表（`colornames`）
- 许可：BSD-3-Clause License（Copyright 2009 The Go Authors），全文见附录 A.2

## go-winres（tc-hib/go-winres）

- 项目：https://github.com/tc-hib/go-winres
- 用途：构建期向 EXE 嵌入图标、版本信息与应用清单（不随程序分发）
- 许可：MIT License

## Elden Ring Nightreign Save Editor

- 项目：https://github.com/alfizari/Elden-Ring-Nightreign-Save-Editor
- 数据修订：`0d2ad1494c372098e689c23159656df70ff2d76d`
- 用途：游戏参数导出、官方简体中文 FMG、合法性实现交叉验证；
  「存档检查」的存档格式（BND4 容器 / AES-CBC / 遗物记录布局）解析
  按其实现移植（`internal/savefile`），遗物物品表数据（`resources/relics.json`，
  由 `EquipParamAntique`、`AttachEffectTableParam`、`AntiqueName` FMG 经
  `macos/DataSources/generate_relics.py` 生成）与深夜遗物正负词条配对规则
  亦以其校验器实现为参考
- 许可：MIT License

MIT License

Copyright (c) the Elden Ring Nightreign Save Editor contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## NightreignQuickRef

- 项目：https://github.com/xxiixi/NightreignQuickRef
- 数据修订：`3e23450094c18125ae5665927ed240b18189a040`
- 用途：中文分类、效果说明、叠加性与别名
- 许可：GNU General Public License v3.0

本发行版整体以 GPL-3.0 发布，完整许可证见 `LICENSE`；可修改的词条数据以 JSON 形式随应用与源码一并提供。

## Smithbox

- 项目：https://github.com/vawser/Smithbox
- 参考修订：`b1b644a770f8cc4c8cab452da3a72ff7b91e105a`
- 用途：确认 `compatibilityId` 的参数语义
- 许可：MIT License

## 叮当市场旧站公开 API 归档

- 原网站：https://elden.dingdangmarket.com
- Wayback 快照：2026-03-12
- 用途：恢复 19 条热门词条查询次数与历史别名；不包含原站源代码、品牌素材或用户数据

## 规则实现说明

Windows 应用中的校验器为独立 JavaScript 实现（`renderer/core.js`），并与 macOS 版 Swift 实现使用相同回归用例；规则依据公开游戏参数事实重建：

1. 三条词条必须在所选版本的非零权重池；
2. `effectId` 不能重复；
3. 非 `-1` 的 `compatibilityId` 不能重复；
4. 保存顺序按 `(overrideEffectId, effectId)` 升序。

应用不修改游戏存档，不绕过反作弊，也不与游戏服务器通信。

## 附录：许可全文

### A.1 MIT License

适用：go-webview2（Copyright (c) 2020 John Chadwick, some portions Copyright (c) 2017 Serge Zaitsev）、zenity（Copyright (c) 2024 Nuno Cruces）。

```
MIT License

Copyright (c) 2024 Nuno Cruces

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

go-webview2 的版权行：

```
Copyright (c) 2020 John Chadwick
Some portions Copyright (c) 2017 Serge Zaitsev
```

### A.2 BSD-3-Clause License（Go 项目：golang.org/x/sys、golang.org/x/image）

```
Copyright 2009 The Go Authors.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
   * Neither the name of Google LLC nor the names of its
contributors may be used to endorse or promote products derived from
this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### A.3 3-Clause BSD License（Microsoft Edge WebView2 SDK）

```
Copyright (C) Microsoft Corporation. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
   * The name of Microsoft Corporation, or the names of its contributors 
may not be used to endorse or promote products derived from this
software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### A.4 ISC License（go-winloader）

```
ISC License

Copyright © 2021, John Chadwick <john@jchw.io>

Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
```
