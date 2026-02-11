# 🚀 Meu Fedora Bootc Customizado

Este repositório contém a "receita" para o build automatizado da minha imagem de sistema operacional baseada em **Fedora 43**. O sistema é imutável, focado em performance com drivers **Nvidia** e interface **GNOME**.

## 🛠️ Arquitetura do Projeto

* **Base:** Fedora Linux Versão (43)
* **Interface:** GNOME Shell
* **Drivers:** Nvidia (via Negativo17) incluso na `imagem`.
* **Automação:** GitHub Actions com build diário às **03:45 (Brasília)**.

## 📁 Estrutura de Arquivos

| Arquivo | Função |
| --- | --- |
| `Containerfile` | Instruções de build da imagem (instalação de pacotes e drivers). |
| `pacotes_rpm` | Lista de aplicativos e bibliotecas que o DNF deve instalar. |
| `post-install.sh` | Scripts de configuração pós-instalação (remover fedora flatpak, add flathub e instala os flatpaks). |
| `.github/workflows` | Contém o arquivo .yml do GitHub Actions para o build automático. |
| `10-nvidia-args-.toml` | Configura os parâmetros para colocar nouveau no blacklist. |
| `post-install.service` | Configura um serviço do systemd para baixar os flatpaks no primeiro boot após instalação |
| `vconsole.conf` | Configura o TTY para pt-BR
| `locale.conf` | Configura a localidade do sistema para pt-BR. | 
| `config.toml` | Configura um arquivo Fedora kickstart para criar um ISO com anaconda para instalar a versão da imagem personalizada. |

## ⚙️ Como Atualizar o Sistema

A imagem é reconstruída diariamente às **03h45** (horário de Brasília). Como costumo acordar entre **07h00 e 08h00**, já encontro uma atualização pronta para aplicar logo pela manhã.

Além disso, configurei no GitHub Actions a integração com o bot do Telegram **@Botfather**, que me notifica automaticamente pelo Telegram sempre que o build da imagem é concluído com sucesso ou apresenta alguma falha.

![Imagem](https://i.imgur.com/5Ip7A1N.png)

#### Atualização manual 
1. Abra o terminal.
2. Verifique se há atualizações:
``` 
sudo bootc upgrade --check
```
3. Realize o upgrade 
```
sudo bootc upgrade 
```
4. Verifique os pacotes que foram atualizados, após reiniciar com a nova imagem
```
rpm-ostree db diff
```
5. Se houver mudanças, reinicie o computador:
```
sudo reboot
```
## 🛠️ Comandos de Manutenção

Se você precisar trocar de imagem ou verificar o estado atual:

* **Verificar versão atual:**
```
bootc status
```

* **Voltar para a versão anterior (Rollback):**
```
sudo bootc rollback
```

* **Mudar para esta imagem (Primeira vez):**
```
sudo bootc switch container-registry:tag
```

## 🤖 Criar uma ISO personalizada para instalar a imagem bootc
#### Para criar a imagem personalizada
```
git clone https://github.com/Ferlinuxdebian/bootc-gnome-minimal.git
cd bootc-gnome-minimal
mkdir output
sudo podman build -t bootc-gnome-minimal -f Containerfile
```
#### Para criar a ISO de instalação 
```
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
Após o processo de construção, basta acessar o diretório output e depois bootiso, dentro desse diretório você vai notar uma imagem ISO "install.iso", que você pode usar para instalar o sistema.
