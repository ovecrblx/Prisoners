--!strict
-- Árvore de comportamento: cada nó devolve Success, Failure ou Running por tick. Nó não guarda
-- memória entre ticks — quem lembra é o blackboard do agente. Os campos `_id`/`_type`/`_children`
-- existem para o painel de depuração ler a árvore sem conhecer as classes.
local BehaviourTree = {}

export type Status = "Success" | "Failure" | "Running"

export type Node = {
	Tick: (self: any, agent: any, dt: number) -> Status,
	_id: number,
	_type: string,
	_name: string,
	_children: { Node }?,
}

local nextId = 0

-- Traço desligado é um `if` por nó por tick. Quem liga é o painel de IA, e só enquanto alguém olha.
local tracing = false

function BehaviourTree.SetTracing(on: boolean)
	tracing = on
end

local function stamp(node: any, kind: string, name: string, children: { Node }?): Node
	nextId += 1
	node._id = nextId
	node._type = kind
	node._name = name
	node._children = children

	local inner = node.Tick
	node.Tick = function(self: any, agent: any, dt: number): Status
		local status = inner(self, agent, dt)
		if tracing then
			local trace = agent.Blackboard.__trace
			if trace then
				trace[node._id] = status
			end
		end
		return status
	end

	return node :: Node
end

-- Forma serializável da árvore, para o painel desenhar sem conhecer os nós.
function BehaviourTree.Describe(node: Node): { [string]: any }
	local children: { any } = {}
	for _, child in ipairs(node._children or {}) do
		table.insert(children, BehaviourTree.Describe(child))
	end
	return { id = node._id, type = node._type, name = node._name, children = children }
end

-- Todos os filhos, em ordem: o primeiro que não devolve Success interrompe e responde pelo nó.
function BehaviourTree.Sequence(name: string, children: { Node }): Node
	return stamp({
		Tick = function(_self: any, agent: any, dt: number): Status
			for _, child in ipairs(children) do
				local status = child:Tick(agent, dt)
				if status ~= "Success" then
					return status
				end
			end
			return "Success"
		end,
	}, "Sequence", name, children)
end

-- Primeiro filho que não falha responde pelo nó; todos falharam, o nó falha.
function BehaviourTree.Selector(name: string, children: { Node }): Node
	return stamp({
		Tick = function(_self: any, agent: any, dt: number): Status
			for _, child in ipairs(children) do
				local status = child:Tick(agent, dt)
				if status ~= "Failure" then
					return status
				end
			end
			return "Failure"
		end,
	}, "Selector", name, children)
end

function BehaviourTree.Condition(name: string, predicate: (any) -> boolean): Node
	return stamp({
		Tick = function(_self: any, agent: any, _dt: number): Status
			local ok, result = pcall(predicate, agent)
			if not ok then
				warn(string.format("[BehaviourTree] condição '%s': %s", name, tostring(result)))
				return "Failure"
			end
			return if result then "Success" else "Failure"
		end,
	}, "Condition", name)
end

-- Status fora dos três vira Failure com aviso: devolver nil por engano não pode virar Success.
function BehaviourTree.Action(name: string, run: (any, number) -> Status): Node
	return stamp({
		Tick = function(_self: any, agent: any, dt: number): Status
			local ok, result = pcall(run, agent, dt)
			if not ok then
				warn(string.format("[BehaviourTree] ação '%s': %s", name, tostring(result)))
				return "Failure"
			end
			if result == "Success" or result == "Failure" or result == "Running" then
				return result :: Status
			end
			warn(string.format("[BehaviourTree] ação '%s' devolveu %s.", name, tostring(result)))
			return "Failure"
		end,
	}, "Action", name)
end

-- Sem pcall: erro dentro de um nó já vira Failure com aviso, e erro FORA deles é defeito de
-- montagem da árvore, que tem que aparecer.
function BehaviourTree.Run(root: Node, agent: any, dt: number): Status
	if tracing then
		agent.Blackboard.__trace = {}
	end
	return root:Tick(agent, dt)
end

return BehaviourTree
