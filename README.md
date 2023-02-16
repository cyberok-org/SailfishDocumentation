<h1 align="center">SailFish Documentation</h1>

Все графы будут сгенерированы для следующего контракта и функции withdrawBalance (если не приведён какой-то другой пример):

```solidity
pragma solidity ^0.4.24;

contract Reentrancy {
    mapping (address => uint) userBalance;
   
    function getBalance(address u) view public returns(uint){
        return userBalance[u];
    }

    function addToBalance() payable public{
        userBalance[msg.sender] += msg.value;
    }   

    function withdrawBalance() public{
        // send userBalance[msg.sender] ethers to msg.sender
        // if mgs.sender is a contract, it will call its fallback function
        if( ! (msg.sender.call.value(userBalance[msg.sender])() ) ){
            revert();
        }
        userBalance[msg.sender] = 0;
    }   
}
```


## Начало


Идёт инициализация `Slither`. Из него берут информацию о функциях и переменных для построения зависимостей:

```python
slither_obj = Slither(contract_path, solc=solc_path)
```


## Построение *Callgraph* графа


Для каждой функции из каждого контракта в граф `callgraph` добавляется соответствующая этой функции вершина. Рёбер на этом этапе нет, функции на отдельные иструкции не раскладываются. 

***Замечание**: есть ещё проверки на `internal call` и `external call` для функций, которые так же влияют на граф, но в моём примере эти проверки не прошли.*

<img src="./graphsPictures/callgraph.png" width="70%">


## Построение *ICFG*


Сначала для каждой функции генерируется ***CFG*** -- Control-Flow Graph -- ориентированный граф в каждой вершине которого находится блок с последовательно выполняющимися инструкциями (без условных переходов) и условием перехода в другие блоки, если таковое есть. Ребра же отражают последовательность выполнения этих блоков (какой блок будет выполнен следующим). Для нашего примера будет построен следующий ***CFG*** :

<img src="./graphsPictures/withdrawBalance_cfg.png" width="70%">

Далее по каждому ***CFG*** строится соответствующий ***ICFG*** -- *Inter-procedural Control-Flow Graph* -- отличие которого от ***CFG*** заключается в подстановке соответствующих ***CFG*** графов вместо вызовов других функций контракта (неважно, публичной или приватной). При такой подстановке блок с инструкцией разбивается на части. За отсутствием вызовов других функций в нашем примере разницы между построенными ***CFG*** и ***ICFG*** нет:

<img src="./graphsPictures/withdrawBalance_icfg.png" width="50%">

Однако продемонстрировать разницу графов можно на примере следующего контракта:

```solidity
pragma solidity ^0.4.21;
contract Foo {
    mapping (address => uint256) public balance;
    mapping (address => uint256) public randomValues;

    
    function functionWithPublicFunction(uint256 value) public payable {
       balance[msg.sender] += msg.value;
       publicFunction(value, msg.sender);
    }

    function functionWithPrivateFunction(uint256 value) public payable {
       balance[msg.sender] += msg.value;
       privateFunction(value, msg.sender);
    }

    function publicFunction(uint256 value, address to) public {
        privateFunction(value, msg.sender);
        randomValues[to] *= value;
    }

    function privateFunction(uint256 value, address to) private {
        randomValues[to] += value;
    }
}
```

Для него будут сгенерированы следующие графы:
- ***CFG***:
<img src="./graphsPictures/functionWithPublicFunction_cfg.png" width="60%">

- ***ICFG***:
<img src="./graphsPictures/functionWithPublicFunction_icfg.png" width="35%">


## Построение *range* графа


Для каждой функии находятся все внутренние зависимости от глобальных переменных. `SailFish` визуализирует их как ориентированный граф с ребрами от вершин с условиями к вершинам с самими переменными. На нашем примере условие выражается вызовом некоторой функции, обозначенной как `U`:

<img src="./graphsPictures/withdrawBalance_range_2.png" width="35%">

Так же полезно будет рассмотреть пример следующей функции с $3$-мя внутренними изменениями глобальных переменных:

```solidity
function withdrawAllBalance() public {
    uint creditBalance = creditAmount[msg.sender];
    
    if (creditBalance > 0 && !creditReward[msg.sender] && flag[msg.sender])
    {
      flag[msg.sender] = false;
      creditReward[msg.sender] = true;
      msg.sender.call.value(creditBalance)("");
      creditAmount[msg.sender] = 0;
    }
  }
```

Для каждого из этих изменений сгенерируется свой `range` граф:

<img src="./graphsPictures/withdrawAllBalance_range_3.png" width="70%">
<img src="./graphsPictures/withdrawAllBalance_range_4.png" width="70%">
<img src="./graphsPictures/withdrawAllBalance_range_5.png" width="70%">


## Построение *SDG*


Для каждой функции создаётся свой ***SDG*** -- *Storage Dependency Graph* -- граф, в котором:
- **вершины** -- это либо глобальные переменные, либо блоки операций над этими переменными
- **ребра** -- это отношения между блоками заключающиеся в чтении (*D*), записи (*W*) или порядке исполнения (*O*).

***Замечание**: есть ещё некоторые `modifiers`, но пока они не использовались в примере.*

Для начала функцией `build_simplified_icfg(self)` генерируется ***Simplified ICFG***, содержащий базовые блоки, способные менять состояние контракта (в комментариях написано, что учитываются 1, 4, 6).

В начале этой функции вызывается `self.propagate_state_vars_used()`, использующий алгоритм *bfs*. В этом *bfs* делаются вызовы

```python
successor._pred_state_var_used.update(basic_block._pred_state_var_used)
successor._pred_state_var_used.update(basic_block._state_vars_used)
```

Далее для каждого блока (вершины) из ***ICFG*** упрощаются базовые блоки, которые не нужны для противоречивого состояния.

Если блок пустой и у него есть $2$ предка, то этот блок становиться отдельной $\varphi$-вершиной.

Добавляются рёбра между блоками, если список инструкций не пуст. Так же, если оказывается вершина без предков и потомков, надо убедиться, что вершина добавлена в граф (конец `build_simplified_icfg`).

Пример сгенерированного ***SICFG***:

<img src="./graphsPictures/withdrawBalance_sicfg.png" width="70%">

Далее функция `self.build_sdg(self._contract, self._function, self._sicfg)`, результат сохраняется в `SDG.sdg_generated[self._function]`. Эта функция добавляет *dataflow edges* к `IR` инструкциям.

Ход функции:

К графу ***SICFG*** прикрепляются глобальные переменные, строятся рёбра к ним. Эти зависимости берутся из ***Range*** графа. Результат работы:

<img src="./graphsPictures/withdrawBalance_sdg.png" width="70%">


## Построение *Compose* графа

Интуитивно ***Compose*** граф (или ***Compose SDG***) -- это попытка сэмулировать ***SDG*** при вызове некоторых публичных функций в `fallback`-функции или вызове некоторой удаленной процедуры. В `SailFish` сейчас проверяется только вызов одной публичной функции, но, кажется, данное поведение не так сложно изменить. 

Данное построение выполняется с помощью функции `generate_composed_sdg` в `main_helper.py`, которая действует в несколько этапов и использует следующие функции:
- `analyze_external_call` из `main_helper.py`, которая использует `analyze_call_destination` и `analyze_lowlevelcall_gas` из `main_helper.py` (которые еще что то далее используют, например функции из `Slither`)
- Конструктор структуры `Compose` из `compose.py`, который использует функцию `setup`, которая использует функцию `build_composed_sdg`, которая использует функции `get_dao_composed_sdg` и `get_tod_composed_sdg`

Все эти функции и их роли будут подробнее разобраны далее:


### Функция *generate_composed_sdg*


1. Идёт отбрасывание приватных функций и конструкторов.

2. Если в функции имеется `external_call`, то вызывается функция `analyze_external_call`. Эта функция, если вызов создает новый контракт, создает и добавляет в имеющийся ***SDG*** соответствующий подграф, иначе вызываются функции `analyze_call_destination` и `analyze_lowlevelcall_gas` для рассматриваемого блока.
 
   ***Замечание**: в последних двух функциях используется `Slither`.*

3. Если функция отправляет `ether` или имеет `external_call`, то для неё создаётся стуктура `Compose`, которая запоминается в `composed_sdg[function]`.


### Конструктор структуры *Compose*


Инициализируют некоторые поля, после чего вызывает функцию-член `setup()` для заполнения этих полей.


### Функция *setup*


Обертка над функцией `build_сomposed_sdg`, которая после работы функции дополнительно генерирует рисунки с помощью функции `print_sdg_dot`.


### Функция *build_composed_sdg*


1. Собирает список всех ***SDG***, а так же всех их вершин с данными и инструкциями. 
2. Собранные данные потенциально передаются в $2$ функции:
   - При установленных флагах `dao` и `external_call` вызывается функция `get_dao_composed_sdg`, которая заполняет поля `self._dao_composed_sdgs` и 
   `self._dao_composed_sdg_to_call_predecessors`
   - При установленных флагах `tod` и `is_ether_sending` вызывается функция `get_dao_composed_sdg`, которая заполняет поля `self._tod_composed_sdgs` и 
   `self._tod_composed_sdg_to_call_predecessors`


### Функция *get_dao_composed_sdg*

1. Создаётся словарь словарей `composed_sdgs`. Первым ключём является функция, для которой мы создавали `Compose` (далее `target_sdg`), второй ключ -- сопоставляемая ей функция. Значением же является *tuple* из 4 элементов -- `(composed_sdg, graph_node, modified_sdg, matching_sdg)`.

2. Перебираются вершины c инструкциями из `target_sdg`. Анализ начнётся только если тип инструкции в этой вершине имеет значение `LowLevelCall` или `HighLevelCall`. Для анализа создается копия `target_sdg` под названием `modified_sdg`.

3. Если все проверки прошли, то находятся все вершины, которые стоят не позже вершины с `external_call`. После этого из `modified_sdg` удаляются все ребра до хранилища, не исользуемые найденными вершинами (оптимизация).

4. Далее перебираются все кандидаты `matching_sdg` на подстановку вместо внешнего вызова. Они переданы списком через аргумент `all_sdgs` нашей функции. 

5. Граф `matching_sdg` вставляется в `modified_sdg` с помощью встроенной в библиотеку `networkx` функции `compose(modified_sdg, matching_sdg)`. Результат записывается в локальную переменную `composed_sdg`.

6. Удаляются лишние ребра и добавляются пометки на ребрах:
```python
self.remove_edges(composed_sdg, [graph_node], successors)
self.add_src_to_dest_edges(composed_sdg, [graph_node], root_nodes, function_start)
self.add_src_to_dest_edges(composed_sdg, leaf_nodes, successors, function_end)
```

7. Структура `composed_sdgs` дополняется полученным *tuple* `(composed_sdg, graph_node, modified_sdg, matching_sdg)`.


## Нахождение уязвимостей в блоке *detection*


Для каждой композиции двух функций вызывается метод `detect_dao_read_write_dependencies`, в который передаётся информация о графе и о том, из каких двух графов он состоял (`primary_sdg` и `matched_sdg`).

Идёт перебор всех глобальных переменных в графе. Для этой глобальной переменной перебираются предки и потомки. После для каждой пары предка и потомка  с помощью битовой логики идёт проверка, что ровно одна из этих вершин находится в `primary_sdg` (то есть в изначальном графе до композиции). Одну из этих вершин называют `start_node`, а другую -- `end_node` . Далее идёт дополнительная проверка, что межу этимии вершинами есть путь не через глобальные переменные.

Далее идёт вызов `self.output_paths(matched_function, start_node, primary_function, end_node, call_node, all_predecessors)` для нахождения пути атаки (результат сохраняется в `composed_graph`) и генерация `symex_path.json` для этого графа.


### Функция *output_paths*

Для начала берутся все вершины из `primary_icfg`, которые лежат на пути от начала функции до вызова *call* и запомаинаются в `subgraph_1`. Затем берутся вершины из `matching_icfg` между началом этой функции и до конца `start_node`, в которой наблюдается первое ребро D/W. Затем бурутся все вершины на пути из `start_node` до конца `matching_function`. Результат запоминается в `subgraph_2`. Далее `subgraph_1` и `subgraph_2` соездиняются по `call_node` в `composed_graph_12`. Далее берутся все вершины на пути из вызова *call* до `end_node`, где наблюдается второе ребро D/W. Результат запоминается в `subgraph_3`, который потом скрепляется с `composed_graph_12` и получается `composed_graph_123`, который и является рузультатом *output_paths*.