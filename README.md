# Fedora Bootc Imagem Personalizada

Este repositório contém a definição da imagem de sistema operacional baseada em **Fedora 44**, construída com `bootc`. O sistema é imutável, voltado para uso desktop com suporte a drivers Nvidia e interface GNOME.

Além do `bootc`, a imagem utiliza o [chunkah](https://github.com/coreos/chunkah) para otimizar o processo de atualização, dividindo a imagem em camadas adicionais e reduzindo o volume de dados transferidos a cada novo build.

## Arquitetura do Projeto

- **Base:** Fedora Linux 44
- **Interface:** GNOME Shell
- **Drivers:** Nvidia via repositório Negativo17, incluídos na imagem
- **Automação:** GitHub Actions com build diário às 03h45 (horário de Brasília)

## Estrutura de Arquivos

| Arquivo | Função |
|---|---|
| `Containerfile` | Instruções de build da imagem (instalação de pacotes e drivers) |
| `pacotes_desktop` | Lista de pacotes relacionados à interface gráfica (GNOME, Plasma e afins) |
| `pacotes_necessarios` | Lista de pacotes essenciais ao sistema, acrescida de pacotes de escolha pessoal |
| `post-install.sh` | Script de pós-instalação: remove o repositório Fedora Flatpak, adiciona o Flathub e instala os Flatpaks |
| `.github/workflows` | Arquivo `.yml` responsável pelo build automático via GitHub Actions |
| `10-nvidia-args.toml` | Parâmetros para colocar o driver `nouveau` no blacklist |
| `post-install.service` | Serviço systemd que executa o script de pós-instalação no primeiro boot |
| `vconsole.conf` | Configuração do TTY para pt-BR |
| `locale.conf` | Configuração de localidade do sistema para pt-BR |
| `config.toml` | Arquivo de kickstart do Anaconda para geração de ISO de instalação |
| `zram-generator.conf` | Configura o zram com tamanho igual ao da RAM, usando o algoritmo de compressão zstd |

## Ciclo de Atualização

A imagem é reconstruída automaticamente todos os dias às 03h45. Uma notificação via Telegram (integração com o BotFather) é enviada ao final de cada build, indicando sucesso ou falha.

![Notificação Telegram](https://i.imgur.com/5Ip7A1N.png)

### Atualização manual

```bash
# Verificar se há nova imagem disponível
sudo bootc upgrade --check

# Aplicar a atualização
sudo bootc upgrade

# Após reiniciar, verificar o que mudou
rpm-ostree db diff

# Reiniciar para ativar a nova imagem
sudo reboot
```

## Comandos de Manutenção

```bash
# Ver a versão atual da imagem
bootc status

# Reverter para a imagem anterior
sudo bootc rollback

# Migrar para esta imagem (primeira utilização)
sudo bootc switch container-registry:tag
```

## Criação de ISO Personalizada

### Build da imagem local

```bash
git clone https://github.com/Ferlinuxdebian/bootc-gnome-minimal.git
cd bootc-gnome-minimal
mkdir output
sudo podman build -t bootc-gnome-minimal -f Containerfile
```

### Geração da ISO de instalação

```bash
sudo podman run \
    --rm \
    -it \
    --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    -v ./output:/output \
    -v ./config.toml:/config.toml:ro \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type anaconda-iso \
    --rootfs btrfs \
    localhost/bootc-gnome-minimal
```

Após a conclusão, o arquivo `output/bootiso/install.iso` estará disponível para uso na instalação do sistema.
