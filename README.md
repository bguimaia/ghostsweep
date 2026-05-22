# GhostSweep

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0-orange.svg)](https://github.com/bguimaia/ghostsweep/releases)
[![Platform](https://img.shields.io/badge/platform-Windows-0078D4?logo=windows&logoColor=white)]()
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)]()
[![No Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)]()

**Remove macOS ghost files from any Windows folder — no installs, no dependencies, no admin rights.**

`.DS_Store` · `._*` resource forks · `__MACOSX` · `.Spotlight-V100` · `.Trashes`

---

## Why this exists

If you work with macOS files on Windows — shared drives, external hard drives, Google Drive, ZIP archives from a Mac — you've seen the ghost: invisible metadata files that macOS leaves behind everywhere. On Windows they show up as broken files, pollute search results, and confuse collaborators.

GhostSweep is a single PowerShell script that opens a GUI window, scans for those files, and removes them cleanly — sending everything to the Recycle Bin so nothing is lost by accident.

---

## Highlights

- **Zero dependencies** — pure PowerShell + WPF. Ships as one `.ps1` file. Runs on any Windows without installing anything.
- **Safe by default** — deleted files go to the Recycle Bin. Undo anytime with Ctrl+Z in Explorer.
- **Granular control** — enable or disable each file type before scanning. Run only what you need.
- **Keyboard-first** — full workflow without touching the mouse. Scan → review → delete → done.
- **Folder history** — remembers your last 5 folders, persisted across sessions.
- **Audit trail** — export a timestamped log with breakdown by type and full path list.
- **Adaptive UI** — window scales to your screen resolution. Works from 1280px up to 4K.

---

## Installation

**Option 1 — One-liner** (no download required):

```powershell
irm "https://raw.githubusercontent.com/bguimaia/ghostsweep/main/ghostsweep.ps1" | iex
```

Open PowerShell, paste, press Enter. The window opens immediately.

**Option 2 — Download and run:**

1. Download `ghostsweep.ps1` and `GhostSweep.bat` to the same folder
2. Double-click `GhostSweep.bat`

---

## Usage

```
┌──────────────────────────────────────────────────────────┐
│  GhostSweep v1.0                                         │
├──────────────────────────────────────────────────────────┤
│  [📁 Select Folder]  C:\Volumes\MyDrive\Project\...      │
│  [☑] Include subfolders        [Advanced Options ▾]      │
├──────────────────────────────────────────────────────────┤
│  48 items found                                          │
│  .DS_Store: 34  ·  ._*: 12  ·  __MACOSX: 2             │
│                                                          │
│  [▶ Show details]                                        │
│                                                          │
│  ████████████████░░░░  68%  33/48                        │
│                                                          │
│  [Scan]    [🗑 Delete All]    [💾 Save Log]              │
│  Status: 33 items deleted · 15 remaining                 │
├──────────────────────────────────────────────────────────┤
│  Enter  scan  ·  Del  delete  ·  Esc  cancel             │
└──────────────────────────────────────────────────────────┘
```

**Step by step:**

1. **Choose a folder** — click *Select Folder*, drag a folder onto the window, type a path directly in the field and press Enter, or click the history button (🕐) to pick a recent folder.
2. **Configure** — toggle *Include subfolders* (on by default). Open *Advanced Options* to enable/disable specific file types.
3. **Scan** — click *Scan* or press `Enter`. Results appear with a count per type.
4. **Review** — click *Show details* to expand a scrollable list of every found path.
5. **Delete** — click *Delete All* or press `Del`. A progress bar tracks deletion in real time.
6. **Save the log** — after deletion, click *Save Log* to export a `.txt` audit file.

---

## Keyboard Shortcuts

| Key     | Action                                      |
| ------- | ------------------------------------------- |
| `Enter` | Start scan (or re-scan after deletion)      |
| `Del`   | Delete all found items (after a scan)       |
| `Esc`   | Cancel running scan or deletion             |

---

## Advanced Options

Click *Advanced Options* to expand the type filter panel. Each file type can be enabled or disabled independently:

| Option              | Default | What it does                                         |
| ------------------- | ------- | ---------------------------------------------------- |
| `.DS_Store`         | ✅ On   | macOS folder metadata files                          |
| `._* (forks)`       | ✅ On   | Resource fork files (prefixed with `._`)             |
| `__MACOSX`          | ✅ On   | Ghost folder left by macOS zip extraction            |
| `.Spotlight-V100`   | ✅ On   | Spotlight search index on external drives            |
| `.Trashes`          | ✅ On   | macOS trash folder on external drives                |
| Include subfolders  | ✅ On   | Recursively scan all nested folders                  |

---

## What it removes

| File / Folder       | Description                                                        |
| ------------------- | ------------------------------------------------------------------ |
| `.DS_Store`         | macOS folder metadata — invisible on Mac, junk on Windows          |
| `._FILENAME`        | Resource forks — appear as corrupted or duplicate files on Windows |
| `__MACOSX/`         | Ghost folder created when extracting macOS ZIP archives on Windows |
| `.Spotlight-V100`   | Spotlight index — leftover on external drives formatted on macOS   |
| `.Trashes`          | macOS trash folder on external drives                              |

---

## Log File

After a deletion, click *Save Log* to export a `.txt` file. The filename includes the timestamp of when the deletion started (e.g. `ghostsweep-2025-06-14_09-32-11.txt`).

Log format:

```
GhostSweep v1.0 — Log de exclusao
==========================================
Inicio:  14/06/2025 09:32:11
Fim:     14/06/2025 09:32:14
Pasta:   C:\Volumes\Drive\Project
Total:   48 items deleted

RESUMO POR TIPO
  .DS_Store         34
  ._* (forks)       12
  __MACOSX           2

ITENS DELETADOS
14/06/2025 09:32:11   C:\Volumes\Drive\Project\.DS_Store
14/06/2025 09:32:11   C:\Volumes\Drive\Project\Assets\.DS_Store
...
```

---

## Contributing

Contributions are welcome. Feel free to open issues, suggest features, or submit pull requests.

---

## Requirements

- Windows 8.1 or later
- Windows PowerShell 5.1+ **or** PowerShell 7+
- No admin rights required

---

## Made by

Built by **Bruno Maia** and **Claude**.

- [github.com/bguimaia](https://github.com/bguimaia)

---

## License

[MIT](LICENSE)

---
---

# GhostSweep

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0-orange.svg)](https://github.com/bguimaia/ghostsweep/releases)
[![Platform](https://img.shields.io/badge/platform-Windows-0078D4?logo=windows&logoColor=white)]()
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)]()
[![No Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)]()

**Remove arquivos fantasma do macOS de qualquer pasta no Windows — sem instalar nada, sem dependências, sem permissão de administrador.**

`.DS_Store` · `._*` resource forks · `__MACOSX` · `.Spotlight-V100` · `.Trashes`

---

## Por que isso existe

Se você trabalha com arquivos de Mac no Windows — drives compartilhados, HDs externos, Google Drive, ZIPs enviados de um Mac — já viu o fantasma: arquivos de metadados invisíveis que o macOS deixa para trás em toda pasta que toca. No Windows eles aparecem como arquivos corrompidos, poluem buscas e confundem colaboradores.

GhostSweep é um único script PowerShell que abre uma janela, escaneia esses arquivos e os remove com segurança — enviando tudo para a Lixeira para que nada seja perdido por acidente.

---

## Destaques

- **Zero dependências** — PowerShell puro + WPF. Distribuído como um único `.ps1`. Funciona em qualquer Windows sem instalar nada.
- **Seguro por padrão** — arquivos deletados vão para a Lixeira. Desfaça com Ctrl+Z no Explorer.
- **Controle granular** — ative ou desative cada tipo de arquivo antes de escanear.
- **Workflow por teclado** — fluxo completo sem precisar do mouse.
- **Histórico de pastas** — lembra as últimas 5 pastas usadas, persistido entre sessões.
- **Trilha de auditoria** — exporte um log com timestamps, resumo por tipo e lista completa de caminhos.
- **Interface adaptável** — janela escala com a resolução da tela. Funciona de 1280px até 4K.

---

## Instalação

**Opção 1 — One-liner** (sem download):

```powershell
irm "https://raw.githubusercontent.com/bguimaia/ghostsweep/main/ghostsweep.ps1" | iex
```

Abra o PowerShell, cole e pressione Enter. A janela abre imediatamente.

**Opção 2 — Download e execução:**

1. Baixe `ghostsweep.ps1` e `GhostSweep.bat` na mesma pasta
2. Duplo clique no `GhostSweep.bat`

---

## Modo de uso

```
┌──────────────────────────────────────────────────────────┐
│  GhostSweep v1.0                                         │
├──────────────────────────────────────────────────────────┤
│  [📁 Selecionar Pasta]  C:\Volumes\Drive\Projeto\...     │
│  [☑] Incluir subpastas      [Opções Avançadas ▾]         │
├──────────────────────────────────────────────────────────┤
│  48 itens encontrados                                    │
│  .DS_Store: 34  ·  ._*: 12  ·  __MACOSX: 2             │
│                                                          │
│  [▶ Mostrar detalhes]                                    │
│                                                          │
│  ████████████████░░░░  68%  33/48                        │
│                                                          │
│  [Escanear]  [🗑 Deletar tudo]  [💾 Salvar log]          │
│  Status: 33 itens deletados · 15 restantes               │
├──────────────────────────────────────────────────────────┤
│  Enter  escanear  ·  Del  deletar  ·  Esc  cancelar      │
└──────────────────────────────────────────────────────────┘
```

**Passo a passo:**

1. **Escolha uma pasta** — clique em *Selecionar Pasta*, arraste uma pasta para a janela, digite um caminho diretamente no campo e pressione Enter, ou clique no botão de histórico (🕐) para escolher uma pasta recente.
2. **Configure** — ative/desative *Incluir subpastas* (ativo por padrão). Abra *Opções Avançadas* para habilitar ou desabilitar tipos específicos de arquivo.
3. **Escanear** — clique em *Escanear* ou pressione `Enter`. O resultado aparece com contagem por tipo.
4. **Revisar** — clique em *Mostrar detalhes* para expandir a lista rolável com o caminho de cada arquivo encontrado.
5. **Deletar** — clique em *Deletar tudo* ou pressione `Del`. Uma barra de progresso acompanha a deleção em tempo real.
6. **Salvar o log** — após a deleção, clique em *Salvar log* para exportar um arquivo `.txt` de auditoria.

---

## Atalhos de teclado

| Tecla   | Ação                                             |
| ------- | ------------------------------------------------ |
| `Enter` | Iniciar escaneamento (ou re-escanear)            |
| `Del`   | Deletar todos os itens encontrados               |
| `Esc`   | Cancelar escaneamento ou deleção em andamento    |

---

## Opções Avançadas

Clique em *Opções Avançadas* para expandir o painel de filtro por tipo. Cada tipo pode ser ativado ou desativado independentemente:

| Opção               | Padrão  | O que faz                                             |
| ------------------- | ------- | ----------------------------------------------------- |
| `.DS_Store`         | ✅ Ativo | Arquivos de metadados de pasta do macOS               |
| `._* (forks)`       | ✅ Ativo | Resource forks (prefixados com `._`)                  |
| `__MACOSX`          | ✅ Ativo | Pasta fantasma criada ao descompactar ZIPs no Mac     |
| `.Spotlight-V100`   | ✅ Ativo | Índice de busca do Spotlight em drives externos       |
| `.Trashes`          | ✅ Ativo | Lixeira do macOS em drives externos                   |
| Incluir subpastas   | ✅ Ativo | Escanear recursivamente todas as subpastas            |

---

## O que remove

| Arquivo / Pasta     | Descrição                                                           |
| ------------------- | ------------------------------------------------------------------- |
| `.DS_Store`         | Metadados de pasta do macOS — invisível no Mac, lixo no Windows     |
| `._ARQUIVO`         | Resource forks — aparecem como arquivos corrompidos no Windows      |
| `__MACOSX/`         | Pasta fantasma criada ao descompactar ZIPs do macOS no Windows      |
| `.Spotlight-V100`   | Índice do Spotlight — sobra em drives externos formatados no macOS  |
| `.Trashes`          | Lixeira do macOS em drives externos                                 |

---

## Arquivo de log

Após a deleção, clique em *Salvar log* para exportar um `.txt`. O nome inclui o timestamp de quando a deleção iniciou (ex: `ghostsweep-2025-06-14_09-32-11.txt`).

Formato do log:

```
GhostSweep v1.0 — Log de exclusao
==========================================
Inicio:  14/06/2025 09:32:11
Fim:     14/06/2025 09:32:14
Pasta:   C:\Volumes\Drive\Projeto
Total:   48 itens deletados

RESUMO POR TIPO
  .DS_Store         34
  ._* (forks)       12
  __MACOSX           2

ITENS DELETADOS
14/06/2025 09:32:11   C:\Volumes\Drive\Projeto\.DS_Store
14/06/2025 09:32:11   C:\Volumes\Drive\Projeto\Assets\.DS_Store
...
```

---

## Contribuindo

Contribuições são bem-vindas. Abra uma issue, sugira funcionalidades ou envie um pull request.

---

## Requisitos

- Windows 8.1 ou superior
- Windows PowerShell 5.1+ **ou** PowerShell 7+
- Sem necessidade de permissão de administrador

---

## Feito por

Desenvolvido por **Bruno Maia** e **Claude**.

- [github.com/bguimaia](https://github.com/bguimaia)

---

## Licença

[MIT](LICENSE)
