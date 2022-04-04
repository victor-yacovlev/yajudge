# Расположение и форматы файлов

## Курсы и задачи

В системе yajudge используются два независимых хранилища в разных каталогах:
 - каталог с пулом задач, определяемый параметром `problems_root` конфигурационного
 файла `/etc/yajudge/master-$CONFIG_NAME.yaml`
 - каталог с курсами, - параметр `courses_root`; каждый курс хранится в отдельном подкаталоге.


## Форматы конфигурационных файлов задач и курсов

Почти везде используется формат [YAML](https://yaml.org). Исключением являются тексты уроков (readings)
и условия задач, которые представляются в простом текстовом формате [Markdown](https://ru.wikipedia.org/wiki/Markdown). 