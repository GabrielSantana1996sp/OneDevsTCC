# OneDevsOS - AlbertEinstein
- Uma distribuição Linux focada em desenvolvimento e segurança DevSecOps, baseada no Debian Trixie.

# Descrição
O OneDevsOS é uma distribuição Linux personalizada construída sobre o Debian Trixie, otimizada para desenvolvedores e profissionais de segurança. Inclui ferramentas de desenvolvimento, pentest, DevOps e segurança em um ambiente XFCE leve e personalizável.

Características Principais
Base Debian Trixie: Estabilidade e vasta gama de pacotes
Ambiente XFCE: Desktop leve e personalizável
Ferramentas de Desenvolvimento: Python, Java, Go, Node.js, Rust, Ruby e mais
Ferramentas de Pentest: Nmap, Wireshark, Aircrack-ng, John the Ripper, etc.
Ferramentas DevSecOps: Docker, Podman, Ansible, AppArmor, Fail2ban, ClamAV
Instalador Calamares: Interface gráfica amigável para instalação
Nix Package Manager: Incluído para gerenciamento avançado de pacotes
Requisitos do Sistema
Processador: 64-bit (x86_64)
Memória RAM: Mínimo 2GB, recomendado 4GB+
Espaço em disco: Mínimo 20GB para instalação
Sistema UEFI ou BIOS com suporte a inicialização
Como Construir a ISO
Pré-requisitos
Debian Trixie ou derivado
Conexão com internet (para primeira construção)
Acesso sudo
Instalação de Dependências
O script de construção instalará automaticamente as dependências necessárias:

debootstrap
live-build
xorriso
squashfs-tools
syslinux-common
isolinux
Construindo a ISO
Clone este repositório:
bash
git clone https://github.com/GabrielSantana1996sp/OneDevsTCC.git
cd OneDevsTCC
Torne o script executável:
bash
chmod +x build.sh
Execute o script de construção:
bash
sudo ./build.sh
O processo de construção pode levar de 1 a 2 horas, dependendo da velocidade da sua conexão e do seu hardware.

Opções de Construção
Modo offline: O script detectará automaticamente se há conexão com internet
Limpeza: Execute sudo ./build.sh clean para limpar o ambiente de construção
Apenas geração de arquivos: Execute sudo ./build.sh generate_only para gerar apenas os arquivos de configuração
Testando a ISO
Você pode testar a ISO gerada usando QEMU:

bash
qemu-system-x86_64 -m 4096 -cdrom onedevsos-alberteinstein-1.0-amd64.iso -boot d -enable-kvm
Instalação
Inicie a partir da ISO gerada
Clique no ícone "Instalar OneDevsOS" na área de trabalho
Siga as instruções do instalador Calamares
Após a instalação, remova a mídia e reinicie
Configurações Padrão
Usuário Live: dev / Senha: live
Ambiente Desktop: XFCE
Gerenciador de Login: LightDM
Tema: OneDevsOS personalizado
Estrutura do Projeto
.
├── build.sh              # Script principal de construção
├── config/               # Arquivos de configuração do live-build
│   ├── package-lists/    # Listas de pacotes a serem instalados
│   ├── hooks/            # Scripts executados durante a construção
│   ├── includes.chroot/  # Arquivos incluídos no sistema final
│   └── apt/              # Configurações do APT
└── README.md             # Este arquivo
Licença
Este projeto é licenciado sob a Licença Apache 2.0. Veja o arquivo LICENSE para mais detalhes.

Contribuição
Contribuições são bem-vindas! Sinta-se à vontade para abrir issues ou enviar pull requests.

Contato
E-mail: onedevsofficial@proton.me
Projeto: https://github.com/GabrielSantana1996sp/OneDevsTCC
Agradecimentos
Este projeto é baseado em:

Debian GNU/Linux
Debian Live Build
XFCE Desktop Environment
Calamares Installer
