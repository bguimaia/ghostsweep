# GhostSweep

**Remove macOS ghost files from any folder — on Windows. No installs, no dependencies.**

`.DS_Store` · `._*` resource forks · `__MACOSX` · `.Spotlight-V100` · `.Trashes`

---

## Quick Start

**One-liner** — paste in PowerShell and press Enter:

```powershell
irm "https://raw.githubusercontent.com/bguimaia/ghostsweep/main/ghostsweep.ps1" | iex
```

**Or download:** grab `ghostsweep.ps1` + `GhostSweep.bat`, put them in the same folder, double-click the `.bat`.

---

## Features

- **GUI with no dependencies** — pure PowerShell + WPF, ships as a single `.ps1`
- **Drag & drop** — drag a folder straight onto the window
- **Folder history** — remembers your last 5 folders
- **Type filter** — enable/disable each file type before scanning
- **Recursive toggle** — include or skip subfolders
- **Recycle Bin** — deleted files go to the Recycle Bin (undo with Ctrl+Z in Explorer)
- **Real-time progress** — live counter + progress bar with cancel button
- **Expandable detail** — toggle a scrollable list of every found path
- **Save log** — export a `.txt` with timestamps, breakdown by type, and full path list
- **Keyboard shortcuts** — `Enter` scan · `Del` delete · `Esc` cancel

---

## What it removes

| File / Folder       | Description                                                        |
| ------------------- | ------------------------------------------------------------------ |
| `.DS_Store`         | macOS folder metadata (invisible on Mac, junk on Windows)          |
| `._FILENAME`        | Resource forks — show up as corrupted files on Windows             |
| `__MACOSX/`         | Ghost folder created when extracting macOS zips on Windows         |
| `.Spotlight-V100`   | Spotlight search index (leftover on external drives)               |
| `.Trashes`          | macOS trash folder on external drives                              |

---

## Requirements

- Windows 8.1 or later
- Windows PowerShell 5.1+ **or** PowerShell 7+
- No admin rights required

---

## License

MIT

---

---

# GhostSweep

**Remove arquivos fantasma do macOS de qualquer pasta — no Windows. Sem instalar nada.**

`.DS_Store` · `._*` resource forks · `__MACOSX` · `.Spotlight-V100` · `.Trashes`

---

## Inicio rapido

**One-liner** — cole no PowerShell e pressione Enter:

```powershell
irm "https://raw.githubusercontent.com/bguimaia/ghostsweep/main/ghostsweep.ps1" | iex
```

**Ou baixe:** `ghostsweep.ps1` + `GhostSweep.bat` na mesma pasta, duplo clique no `.bat`.

---

## Funcionalidades

- **Interface sem dependencias** — PowerShell puro + WPF, distribuido como um unico `.ps1`
- **Arrastar e soltar** — arraste uma pasta direto para a janela
- **Historico de pastas** — lembra as ultimas 5 pastas usadas
- **Filtro por tipo** — ative/desative cada tipo de arquivo antes de escanear
- **Subpastas** — escolha se inclui ou nao as subpastas
- **Lixeira** — arquivos deletados vao para a Lixeira (recuperavel com Ctrl+Z no Explorer)
- **Progresso em tempo real** — contador ao vivo + barra de progresso com botao de cancelar
- **Lista detalhada** — expanda para ver o caminho completo de cada arquivo encontrado
- **Salvar log** — exporte um `.txt` com timestamps, resumo por tipo e lista completa
- **Atalhos de teclado** — `Enter` escanear · `Del` deletar · `Esc` cancelar

---

## O que remove

| Arquivo / Pasta     | Descricao                                                           |
| ------------------- | ------------------------------------------------------------------- |
| `.DS_Store`         | Metadados de pasta do macOS (invisivel no Mac, lixo no Windows)     |
| `._ARQUIVO`         | Resource forks — aparecem como arquivos corrompidos no Windows      |
| `__MACOSX/`         | Pasta fantasma criada ao descompactar zips do macOS no Windows      |
| `.Spotlight-V100`   | Indice de busca do Spotlight (sobra em drives externos)             |
| `.Trashes`          | Lixeira do macOS em drives externos                                 |

---

## Requisitos

- Windows 8.1 ou superior
- Windows PowerShell 5.1+ **ou** PowerShell 7+
- Sem necessidade de permissao de administrador

---

## Licenca

MIT
