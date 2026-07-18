# .NET Framework → Modern .NET Retarget Guide (UI stack preserved)

A repeatable process to move **any** legacy .NET Framework app to the **best‑supported
modern .NET** (latest LTS) **without changing the UI technology** (WinForms stays
WinForms, console stays console, libraries stay libraries). This is a *retarget /
lift‑and‑shift*, not a rewrite.

Pair this checklist with **`Convert-DotNetApp.ps1`** (the automation) and the worked
example in **`SourceCode-net10/MIGRATION-REPORT.md`**.

---

## 0. Decide the target
- **Best supported = latest LTS.** Use `LTS` with the Upgrade Assistant, or pin the TFM
  (e.g. `net10.0-windows` for a Windows desktop app).
- Desktop apps must use the `-windows` TFM and `UseWindowsForms=true` / `UseWPF=true`.

## 1. Baseline & safety
1. Work on a **copy** of the source (never the only copy).
2. Record the current TFMs, references, COM refs, `app.config`, and any 3rd‑party DLLs.
3. Confirm SDKs: `dotnet --list-sdks` / `--list-runtimes` (need the target LTS + desktop pack).

## 2. Convert project files to SDK‑style
- Run `Convert-DotNetApp.ps1 -Path <sln> -TargetFramework LTS` **or** hand‑author
  SDK‑style `.csproj` (recommended when there are COM refs, stale HintPaths, or custom
  culture resources — the tool cannot fix those).
- SDK‑style essentials:
  - `<UseWindowsForms>true</UseWindowsForms>` (WinForms) — pulls in the desktop framework refs implicitly; **delete** explicit `System`, `System.Drawing`, `System.Windows.Forms`, `System.Xml`, `System.Core`, `System.Data` references.
  - `<GenerateAssemblyInfo>false</GenerateAssemblyInfo>` if a hand‑written `AssemblyInfo.cs` exists (avoids duplicate‑attribute errors).
  - `<Deterministic>false</Deterministic>` if `AssemblyVersion` uses a `*` wildcard.
  - Default file globbing replaces the huge explicit `<Compile>`/`<EmbeddedResource>` lists — but **`<Compile Remove>`/`<EmbeddedResource Remove>`** any files that were present on disk yet *excluded* from the old project (tests, dead forms, duplicates), or they will now be compiled.

## 3. Resolve the common blockers (code/runtime)

| Blocker (Framework) | Symptom on modern .NET | Fix |
|---|---|---|
| **`SerialPort`** (was in `System.dll`) | CS1069 "forwarded to System.IO.Ports" | `PackageReference System.IO.Ports` |
| **`System.Data.OleDb` / Jet / ACE (Access)** | Missing type / 32‑bit provider | `PackageReference System.Data.OleDb`; set **`PlatformTarget=x86`** (Jet/ACE are 32‑bit) |
| **ADO/ADOX/ADODB, other COM** | COM types missing; `tlbimp` needs registered type libs | Prefer referencing the **already‑built interop assemblies** (`Interop.*.dll`, PIAs) via `HintPath`; or `<COMReference>` if the type libs are registered. Drop unused COM refs (verify they're referenced in code first). |
| **MS Chart** `System.Windows.Forms.DataVisualization` | Assembly not in modern .NET | `PackageReference WinForms.DataVisualization` (same namespace, drop‑in) |
| **`app.config` userSettings / connectionStrings** | `ConfigurationManager` / `Settings` types missing | `PackageReference System.Configuration.ConfigurationManager` |
| **`System.Web` / `System.Web.Services` (ASMX client)** | Assemblies not in modern .NET | If the app actually calls SOAP: regenerate with `dotnet-svcutil` (WCF/CoreWCF). **Often these refs are dead** (raw `HttpWebRequest` is used) — just delete them. |
| **Custom OS‑registered cultures** (`CultureAndRegionInfoBuilder`/`sysglobl`) | `new CultureInfo("metric-en-US")` throws `CultureNotFoundException` (invalid BCP‑47) | **Rename** localized `*.resx` to real cultures (e.g. `de-DE`, `hu-HU`, `en-GB`) and add a small helper mapping the persisted legacy name → real `CultureInfo`. Route all `new CultureInfo(legacyName)` through it. |
| **`System.Design`** design‑time types | Assembly missing | `UITypeEditor`, `ControlDesigner`, `IWindowsFormsEditorService` etc. now ship with the WinForms desktop pack — just drop the `System.Design` reference. |
| **3rd‑party FX DLLs** (e.g. licensing) | CS1701/MSB3277 compat warnings | Reference via `HintPath`; suppress `CS1701;CS1702;MSB3277;NU1701`. Verify it loads at runtime. |

Useful `<NoWarn>` while retargeting: `CA1416` (Windows‑only APIs), `WFO1000` (new WinForms
designer analyzer), `CS1701;CS1702;MSB3277;NU1701` (referencing legacy FX assemblies).

## 4. Resources / localization correctness
- Keep the **`RootNamespace`** identical to the original so auto‑generated manifest
  resource names still match what `Designer.cs` `ResourceManager(...)` expects.
- Set `<GenerateResourceUsePreserializedResources>true</GenerateResourceUsePreserializedResources>`
  for resx that embed serialized objects/images.

## 5. Platform / bitness
- If the app depends on 32‑bit COM/OLEDB (Jet/ACE/ADOX), set `<PlatformTarget>x86</PlatformTarget>`.
  Leave the solution/project `Platform` at the default (`AnyCPU`) so `.slnx` solution
  builds work; `PlatformTarget=x86` still forces a 32‑bit apphost. Confirm with the PE
  machine header (`0x014C` = 32‑bit).

## 6. Validate
1. `dotnet build <sln>` → **0 errors** (warnings triaged).
2. Verify the executable and **satellite assemblies** (per‑culture `*.resources.dll`) are produced.
3. **Runtime probe** the risky, non‑compile‑provable paths (e.g. that custom/mapped cultures
   actually load their satellites and format correctly) with a tiny console harness that
   `Assembly.LoadFrom`s the built dll — GUI apps can't be smoke‑tested headless.
4. Note environment prerequisites for a full functional test (desktop session, 32‑bit
   Jet/ACE OLEDB provider, any hardware/DB the app needs).

## 7. Things to leave behind
- ClickOnce `<BootstrapperPackage>`, `<PublishFile>`, `<Install*>`, manifest signing —
  drop for a plain build; re‑add packaging (MSIX/ClickOnce) separately if needed.
- Machine‑registration helper tools that used removed APIs (e.g. a
  `CultureAndRegionInfoBuilder` registrar) — no longer needed and cannot run on modern .NET.
