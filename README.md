# Projeto de CI/CD com dbt-core e Google Cloud

Este projeto implementa um fluxo automatizado no Github Actions que realiza testes em modificações feitas nos modelos de dados do dbt-core.

O objetivo final é acelerar os analistas no desenvolvimento de produto de dados através de um ambiente seguro, onde independentemente da complexidade dos dados, seja possível criar e modificar consultas com a certeza de que nenhum outro produto seja afetado negativamente. 


### Tecnologias Usadas

- [GitHub](https://github.com/)
- [GitHub Actions](https://github.com/features/actions)
- [Google BigQuery](https://cloud.google.com/bigquery)
- [Google Cloud Storage](https://cloud.google.com/storage)
- [Poetry](https://python-poetry.org/)
- [dbt-core](https://docs.getdbt.com/)

# Guia de Implementação

Essa documentação vai focar somente na implementação do fluxo, então espera-se que você já tenha:

- Um ambiente virtual Python com a ferramenta de sua escolha (eu escolhi o Poetry)
- Um projeto dbt-core iniciado e associado a um banco de dados de sua escolha (eu escolhi o Big Query).

## Conceitos do dbt-core

Com os requisitos acima feitos, vamos começar falando sobre alguns conceitos importantes de funcionamento do dbt antes de dar os próximos passos.

### Profiles

No dbt-core, é possível definir perfis de execução dos comandos. Esses perfis podem conter configurações e credenciais específicas que ficam definidos no arquivo **profiles.yml**.

Neste fluxo, precisamos de 3 perfis diferentes:

- dev (perfil padrão de desenvolvimento)
- ci (perfil do Github Actions)
- prod (perfil de produção)

O motivo de separar em 3 perfis é justamente definir um ambiente diferente no banco de dados para cada um deles. Neste caso aqui, eu defini **schemas diferentes** para cada um deles, assim, os dados construídos por estes perfis estão isolados entre si.

### manifest.json

Esse arquivo é basicamente uma **fotografia do seu projeto dbt inteiro**.

Ele é gerado ao rodar o comando `dbt compile` e fica dentro da pasta `/target`.

Vamos usá-lo para efeitos de comparação e guardaremos sempre uma cópia desta fotografia de produção (neste projeto, escolhi o Google Cloud Storage).

## Fluxo de CI

Esse é o primeiro passo do fluxo. Aqui o objetivo é verificar se todas as modificações feitas nos modelos de dados vão se integrar com o modelo sem causar erros.

### Gatilho de Execução

```yaml
on:
  pull_request:
    branches:
      - main
    types:
      - opened
      - synchronize
```

Esse trecho define que o CI só é acionado automaticamente quando:
  - Um **Pull Request** é aberto para o branch `main`.
  - O código do Pull Request sofre alterações (`synchronize`).

### Preparação do Ambiente
```yaml
jobs:
  dbt:
    runs-on: ubuntu-latest

    env:
      GCS_BUCKET: ${{ secrets.GCS_BUCKET }}

    steps:
      - name: Checkout do código
        uses: actions/checkout@v4


      - name: Instalar o Poetry
        run: |
          curl -sSL https://install.python-poetry.org | python3 -
          echo "$HOME/.local/bin" >> $GITHUB_PATH


      - name: Instalar dependências
        run: |
          poetry install


      - name: Importar Credenciais do BigQuery e Google Cloud Storage
        env:
          GOOGLE_CREDENTIALS: ${{ secrets.GOOGLE_CREDENTIALS }}
        run: |
          echo "$GOOGLE_CREDENTIALS" > /home/runner/gcp-key.json
          export GOOGLE_APPLICATION_CREDENTIALS="/home/runner/gcp-key.json"


      - name: Autenticar no Google Cloud
        uses: google-github-actions/auth@v2
        with:
          credentials_json: ${{ secrets.GOOGLE_CREDENTIALS }}
          

      - name: Configurar Google Cloud Storage
        uses: google-github-actions/setup-gcloud@v1
        with:
          version: 'latest'
          install_components: 'gsutil'


      - name: Testar conexão do dbt com o BigQuery
        working-directory: ./dbt_project
        run: |
          poetry run dbt debug --target ci
```

Ao começar o fluxo, ele precisa preparar o ambiente para realizar os testes:
- Define a variável `GCS_BUCKET`, que armazena o nome do bucket no Google Cloud Storage (GCS), onde o `manifest.json` de produção será armazenado.
- Faz o checkout na máquina onde o CI está rodando para branch do pull request.
- Instala o `Poetry`, um gerenciador de dependências para Python, necessário para instalar o `dbt` e suas dependências.
- Adiciona o diretório do `Poetry` ao `PATH`.
- Instala todas as dependências do projeto definidas no `pyproject.toml`.
- As credenciais do Google Cloud guardadas nos secrets do Github são armazenadas em um arquivo temporário para autenticação.
- Usa uma action oficial do Google para autenticar a execução no Google Cloud e instala o `gsutil`, ferramenta de linha de comando para interagir com o Google Cloud Storage.
- Por fim, ele executa um teste para assegurar que o dbt está funcionando neste ambiente virtual.


### Compilar projeto com mudanças atuais

```yaml
- name: Compilar modelos dbt
  working-directory: ./dbt_project
  run: |
    poetry run dbt compile --target ci
```

Com o ambiente montado, o primeiro passo é compilar o projeto com as modificações que foram feitas, e essa fotografia será guardada por padrão dentro da pasta `/target`.

### Baixar o `manifest.json` de Produção

```yaml
- name: Baixar manifest.json de prod do Google Cloud Storage
  env:
    GOOGLE_APPLICATION_CREDENTIALS: ${{ secrets.GOOGLE_CREDENTIALS }}
  run: |
    mkdir -p dbt_project/target
    gsutil cp gs://${{ env.GCS_BUCKET }}/manifest.json dbt_project/target_prod/manifest.json
```

Depois disso, ele irá baixar a fotografia do ambiente de produção e vai guardar na pasta `dbt_project/target_prod/manifest.json`.

### Listar modelos modificados/afetados e construí-los

```yaml
- name: Listar modelos modificados
  working-directory: ./dbt_project
  run: |
    poetry run dbt ls --state target_prod --select state:modified+

- name: Executar dbt build slim
  working-directory: ./dbt_project
  run: |
    poetry run dbt build --target ci --defer --state target_prod --select state:modified+
```

Com essas duas fotografias no ambiente, vamos listar os modelos modificados (para fins de auditoria) e depois construí-los no ambiente de CI.

O pulo do gato está neste comando aqui:

    poetry run dbt build --target ci --defer --state target_prod --select state:modified+

Imagine um pull request onde você **modificou a Tabela A** de um banco de dados, e ela possui 2 dependências:

 ```mermaid
graph LR
A[Tabela A]
B[Tabela B]
C[Tabela C]
D[Tabela D]
A --> C
B --> C
C --> D
style A fill:#cc7b0a
style D fill:#268211
style C fill:#268211
```

Com o exemplo acima em mente, vamos destrinchar o que cada parte comando faz:
- `poetry run`: Como estou usando poetry, preciso usar esse comando para rodar o comando do dbt dentro do ambiente virtual criado pelo poetry.
- `dbt build`: Comando usado para construir os modelos e depois testá-los.
- `--target ci`: Aqui eu estou **escolhendo o perfil de ci** para rodar esse comando, ou seja, ele vai executar os modelos em um **schema diferente destinado somente pro CI**.
- `--select state:modified+`: Esse comando seleciona **todos os modelos que foram modificados (amarelo), e o "+" seleciona as suas dependências (verde)**.
- `--state target_prod`: Pro comando acima funcionar, ele precisa de uma fotografia de produção para comparar, e aqui é passado o **diretório do manifest.json de produção**.
- `--defer`: Por último, esse comando aqui serve para **evitar o reprocessamento de modelos que não foram modificados**. No exemplo atual, a Tabela C depende de A e B, mas como B não sofreu nenhuma modificação, **ele vai construir C usando a Tabela A que foi modificada e criada agora, e a Tabela B de produção**. *(sem esse comando, o fluxo levantaria um erro, pois ele vai construir A, e ao construír C, ele não vai encontrar a B, pois ela não foi modificada, logo ela não foi criada no ambiente destinado ao CI)*

No final, este comando vai construir todos os modelos que foram modificados e as suas dependências em um ambiente isolado de teste. Se houver algum erro durante a construção de algum modelo, isso indica que uma modificação feita por você pode estar errada ou afetar outros modelos.

Esse erro será indicado na página do Pull Request, onde será possível realizar o debug.
## Fluxo de CD

Esse é o último passo do fluxo, e aqui a modificação feita no pull request já deve ter passado nos testes do CI e está prestes a ser aplicada no ambiente de produção.

Neste fluxo criaremos o mesmo ambiente acima: com o ambiente testado e com as duas fotografias.

### Aplicação das mudanças em produção

```yaml
  - name: Fazer deploy dos modelos em produção
    working-directory: ./dbt_project
    run: |
      poetry run dbt build --target prod --state target_prod --select state:modified+
```

Este comando é similar ao feito no CI, mas com duas diferenças importantes:

- O `--target` agora é prod, ou seja, **vamos aplicar as mudanças feitas diretamente em produção usando o perfil prod**.
- Não usamos o `--defer` porque já estamos executando isso em produção, onde todas as tabelas não afetadas já existem anteriormente.

Com isso, já aplicamos as mudanças no banco de dados de produção.

### Salvar o manifest.json atualizado no Google Cloud Storage

```yaml
  - name: Atualizar o manifest.json do projeto
    working-directory: ./dbt_project
    run: |
      gsutil cp target/manifest.json gs://${{ env.GCS_BUCKET }}/manifest.json
```

Por fim, precisamos guardar a fotografia com as novas mudanças feitas no Google Cloud Storage.

## Fontes de Documentação

### dbt Core
- **Documentação oficial do dbt Core**:  
  [https://docs.getdbt.com/docs/introduction](https://docs.getdbt.com/docs/introduction)  
  Explica como funciona o `dbt`, incluindo configuração de targets, execução de comandos e boas práticas.

- **Estado do dbt (`--state`)**:  
  [https://docs.getdbt.com/reference/node-selection/state](https://docs.getdbt.com/reference/node-selection/state)  
  Explica como comparar estados de builds anteriores para executar apenas modelos modificados.

- **Seleção de nós no dbt (`--select`)**:  
  [https://docs.getdbt.com/reference/node-selection/syntax](https://docs.getdbt.com/reference/node-selection/syntax)  
  Descreve os operadores de seleção de modelos, incluindo `state:modified+`.

---

### Google Cloud Platform (GCP)
- **Google Cloud Storage (`gsutil`)**:  
  [https://cloud.google.com/storage/docs/gsutil](https://cloud.google.com/storage/docs/gsutil)  
  Guia para usar o `gsutil` para upload/download de arquivos.

- **BigQuery para dbt**:  
  [https://docs.getdbt.com/reference/warehouse-profiles/bigquery](https://docs.getdbt.com/reference/warehouse-profiles/bigquery)  
  Guia oficial sobre a configuração do `dbt` com BigQuery.

---

### GitHub Actions
- **GitHub Actions: Configuração de workflows**:  
  [https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)  
  Explica a sintaxe YAML para definir workflows.

---

### Poetry (Gerenciador de Dependências para Python)
- **Instalação e uso do Poetry**:  
  [https://python-poetry.org/docs/](https://python-poetry.org/docs/)  
  Guia para instalar e usar o `Poetry` para gerenciar pacotes no Python.

- **Execução de comandos no ambiente virtual do Poetry**:  
  [https://python-poetry.org/docs/basic-usage/#using-your-virtual-environment](https://python-poetry.org/docs/basic-usage/#using-your-virtual-environment)  
  Explica como executar comandos dentro do ambiente gerenciado pelo `Poetry`.

