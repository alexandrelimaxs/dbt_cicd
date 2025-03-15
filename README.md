# Projeto de CI/CD com dbt-core e Google Cloud

Esse projeto implementa um fluxo automatizado no Github Actions que realiza testes em modificações feitas nos modelos de dados do dbt-core.

O objetivo final é acelerar os analistas no desenvolvimento de produto de dados através de um ambiente seguro, onde independentemente da complexidade dos dados, seja possível criar e modificar consultas com a certeza de que nenhum outro produto seja afetado negativamente. 


### Tecnologias Usadas

- Github
- Github Actions
- Google Big Query
- Google Cloud Storage
- Poetry
- dbt-core

# Guia de Implementação

Essa documentação vai focar somente na implementação do fluxo, então espera-se que você já tenha:

- Um ambiente virtual Python com a ferramenta de sua escolha (eu escolhi o Poetry)
- Um projeto dbt-core iniciado e associado a um banco de dados de sua escolha (eu escolhi o Big Query).

## Conceitos do dbt-core

Com os requisitos acima feitos, vamos começar falando sobre alguns conceitos básicos de funcionamento do dbt para dar os próximos passos sabendo o que e o porque estamos fazendo.

### Profiles

No dbt-core, é possível definir perfis de execução dos comandos. Esses perfis podem conter configurações e credenciais específicas que ficam definidos no arquivo **profiles.yml**.

Neste fluxo, precisamos de 3 perfis diferentes:

- dev (perfil padrão de desenvolvimento)
- ci (perfil do Github Actions)
- prod (perfil de produção)

O motivo de separar em 3 perfis é justamente definir um ambiente diferente no banco de dados pra cada um deles. Neste caso aqui, eu defini **schemas diferentes** pra cada um deles, assim, os dados construídos por estes perfis estão isolados entre si.

### manifest.json

Esse arquivo é basicamente uma **fotografia do seu projeto dbt inteiro**.

Ele é gerado ao rodar o comando `dbt compile` e fica dentro da pasta `/target`.

Vamos usá-lo para efeitos de comparação e guardaremos sempre uma cópia desta fotografia de produção (neste projeto, escolhi o Google Cloud Storage).

## Fluxo de CI

Esse é o primeiro passo do fluxo. Aqui o objetivo é verificar se todas as modificações feitas nos modelos de dados vão se integrar com o modelo sem causar erros.

Assim que um pull request for aberto, ele vai criar uma máquina virtual Ubuntu e criar um ambiente réplica da branch em questão.

Com o ambiente testado e funcionando, o primeiro passo é compilar o projeto com as modificações que foram feitas, e essa fotografia será guardada por padrão dentro da pasta `/target`.

Depois disso, ele irá baixar a fotografia do ambiente de produção e vai guardar na pasta `/target_prod`.

Com essas duas fotografias, o pulo do gato está neste comando aqui:

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
style A fill:#f7c245
style D fill:#66f745
style C fill:#66f745
```

Com o exemplo acima em mente, vamos destrinchar o que cada parte comando faz:
- `poetry run`: Como estou usando poetry, preciso usar esse comando pra rodar o comando do dbt dentro do ambiente virtual criado pelo poetry.
- `dbt build`: Comando usado pra construir os modelos e depois testá-los.
- `--target ci`: Aqui eu estou **escolhendo o perfil de ci** pra rodar esse comando, ou seja, ele vai executar os modelos em um **schema diferente destinado somente pro CI**.
- `--select state:modified+`: Esse comando seleciona **todos os modelos que foram modificados (amarelo), e o "+" seleciona as suas dependências (verde)**.
- `--state target_prod`: Pro comando acima funcionar, ele precisa de uma fotografia de produção pra comparar, e aqui é passado o **diretório do manifest.json de produção**.
- `--defer`: Por último, esse comando aqui serve pra **evitar o reprocessamento de modelos que não foram modificados**. No exemplo atual, a Tabela C depende de A e B, mas como B não sofreu nenhuma modificação, **ele vai construir C usando a Tabela A que foi modificada e criada agora, e a Tabela B de produção**. *(sem esse comando, o fluxo levantaria um erro, pois ele vai construir A, e ao construír C, ele não vai encontrar a B, pois ela não foi modificada, logo ela não foi criada no ambiente destinado ao CI)*

No final, este comando vai construir todos os modelos que foram modificados e as suas dependências em um ambiente isolado de teste. Se houver algum erro durante a construção de algum modelo, isso indica que uma modificação feita por você pode estar errada ou afetar outros modelos.

Isso fica indicado na página do pull request, e lá é possível fazer o debug.
## Fluxo de CD

Esse é o último passo do fluxo, e aqui a modificação feita no pull request já deve ter passado nos testes do CI e está prestes a ser aplicada no ambiente de produção.

Neste fluxo criaremos o mesmo ambiente acima: ambiente testado e com as duas fotografias.

Feito isso, é necessário mais dois comandos:

    poetry run dbt build --target prod --state target_prod --select state:modified+

Este comando é similar ao feito no CI, mas com duas diferenças importantes:

- O `--target` agora é prod, ou seja, **vamos aplicar as mudanças feitas diretamente em produção usando o perfil prod**.
- Não usamos o `--defer` porque já estamos executando isso em produção, onde todas as tabelas não afetadas já existem anteriormente.

Com isso, já aplicamos as mudanças no banco de dados de produção.

Por fim, precisamos guardar a fotografia com as novas mudanças feitas no Google Cloud Storage.
