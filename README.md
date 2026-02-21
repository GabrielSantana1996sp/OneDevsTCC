# OneDevsOS - AlbertEinstein 1.0

## Sobre o Projeto
O **OneDevsOS** é uma distribuição Linux personalizada, construída sobre o Debian, voltada para desenvolvedores e entusiastas de tecnologia.  
Ele oferece um ambiente completo com ferramentas de programação, DevOps, segurança, servidores e utilitários essenciais, além de um instalador gráfico moderno via **Calamares**.

Este projeto é licenciado sob **Apache License 2.0**, mas pode incluir softwares de terceiros sob GPL, MIT, BSD e outras licenças. Cada componente mantém sua licença original.

---

## Recursos Principais
- **Base Debian (Trixie)**  
- **Ambiente Desktop XFCE** leve e personalizável  
- **Instalador gráfico Calamares** com suporte a:
  - Particionamento automático e manual
  - Criptografia LUKS
  - Configuração de usuários e grupos
- **Ferramentas de Desenvolvimento**: Python, Java, Go, Node.js, Rust, Ruby, C/C++, Git, Vim/Neovim, Geany  
- **DevOps & Containers**: Docker, Podman, Ansible, Systemd-nspawn  
- **Servidores e Bancos de Dados**: Apache, Nginx, PHP, MariaDB  
- **Segurança**: AppArmor, Fail2ban, ClamAV, Auditd, Lynis, Tripwire  
- **Utilitários**: tmux, htop, ranger, synaptic, KeepassXC, GParted, Bluetooth, CUPS  
- **Boot Animado (Plymouth)** com tema OneDevsOS  
- **Branding personalizado** (logo, wallpaper, ícones, slideshow de instalação)

---

## Dependências
Antes de iniciar a build, certifique-se de instalar os pacotes necessários:

```bash
sudo apt-get update && sudo apt-get install -y \
  debootstrap live-build xorriso squashfs-tools \
  syslinux-common isolinux dpkg-dev apt-utils
```

---

## Como Construir a ISO
1. Clone o repositório:
   ```bash
   git clone https://github.com/onedevs/onedevsos.git
   cd onedevsos
   ```

2. Execute o script principal:
   ```bash
   ./Script_ISO
   ```

3. O processo irá:
   - Verificar dependências
   - Gerar arquivos de configuração do **live-build**
   - Baixar pacotes necessários (modo online)
   - Construir a ISO híbrida bootável

4. Ao final, a ISO será gerada com o nome:
   ```
   onedevsos-alberteinstein-1.0-amd64.iso
   ```

---

##  Testando a ISO
Você pode testar rapidamente em uma VM com QEMU:

```bash
qemu-system-x86_64 -m 2048 -cdrom onedevsos-alberteinstein-1.0-amd64.iso -boot d
```

## Licença
Este projeto é distribuído sob a **Apache License 2.0**.  
Softwares de terceiros incluídos mantêm suas licenças originais (GPL, MIT, BSD, etc.).

---
