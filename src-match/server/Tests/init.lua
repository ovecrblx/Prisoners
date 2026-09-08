-- Bateria de testes do MATCH. Espelha a do Lobby (src-lobby/server/Tests) de propósito: mesmo
-- Context, mesmo relatório, mesmo t:knownFailure. Quem sabe rodar uma sabe rodar a outra.
--
-- O QUE ELA PEGA E O QUE NÃO PEGA (não confunda os dois)
--   pega:     invariante de config, lógica pura, determinismo, contrato entre dois donos da mesma
--             pergunta, e a paridade das constantes duplicadas entre os dois places.
--   NÃO pega: física, rede, streaming, GUI, comportamento emergente em Play. Nada aqui prova que a
--             partida "joga bem" — prova que as peças que decidem isso não estão quebradas.
--             Teste tranca o que já sabemos; olhar em Play acha o que ainda não sabemos.
--
-- COMO RODAR — Studio, Command Bar. NÃO precisa estar em Play: é lógica pura, e os módulos sob
-- Source/ e ReplicatedStorage.Shared são requeríveis em Edit.
--     local T = game.ServerScriptService.Tests:Clone(); T.Parent = game.ServerScriptService
--     print(require(T).RunAll().summary); T:Destroy()
--
-- O CLONE NÃO É FRESCURA. `require` cacheia por INSTÂNCIA de ModuleScript pela sessão de Edit
-- inteira: requerer este arquivo direto roda a versão de quando ele foi requerido pela PRIMEIRA vez
-- naquela sessão, mesmo com o Rojo tendo sincronizado o disco. As specs e os módulos de produção já
-- são protegidos por requireFresh; este arquivo é o único que o chamador precisa proteger.
--
-- POR QUE FICA FORA DE Source/
-- Main.server.lua faz LoadModules(Source) e dá require em TODO ModuleScript lá dentro, chamando
-- Init/Start. Uma bateria sob Source/ seria carregada em todo boot de servidor de produção. Aqui,
-- como irmã de Source e não filha, ela é inerte até alguém pedir RunAll de propósito.
--
-- COMO ESCREVER UMA SPEC
--   Um arquivo por assunto, aqui em Tests/, e o nome entra em SPEC_NAMES abaixo.
--   A spec retorna function(t).
--   Bug conhecido AINDA NÃO corrigido: use t:knownFailure. Não quebra o relatório, mas AVISA ALTO se
--   um dia passar — aí o bug foi corrigido e a spec vira t:test normal.

local Tests = {}

-- Ordem importa só para a leitura do relatório. Cada correção nascida de Play vira uma spec aqui, e
-- o nome dela entra nesta lista — spec fora dela não roda, e o runner não tem como saber que existe.
local SPEC_NAMES = {
	"StorageRigSpec",
	"CaseFitSpec",
	"ElevatorSlideSpec",
	"RigLookSpec",
}

local function serialize(value)
	if type(value) == "table" then
		local parts = {}
		for key, item in pairs(value) do
			parts[#parts + 1] = tostring(key) .. "=" .. tostring(item)
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(value)
end

local Context = {}
Context.__index = Context

local function newContext(specName, report)
	return setmetatable({ spec = specName, report = report, _stubs = {} }, Context)
end

-- Erro de asserção sobe como string; o pcall do runner captura.
function Context:assert(cond, msg)
	if not cond then
		error(msg or "asserção falhou", 0)
	end
end

function Context:assertEqual(got, want, msg)
	if got ~= want then
		error(
			string.format(
				"%s\n      esperado: %s\n      obtido:   %s",
				msg or "valores diferentes",
				serialize(want),
				serialize(got)
			),
			0
		)
	end
end

-- Ponto flutuante nunca por ==: tempo, ângulo e curva de atenuação comparados assim dão falha
-- fantasma que só aparece numa máquina.
function Context:assertNear(got, want, tolerance, msg)
	tolerance = tolerance or 1e-9
	if math.abs(got - want) > tolerance then
		error(
			string.format(
				"%s\n      esperado: %s (±%s)\n      obtido:   %s",
				msg or "valores diferentes",
				tostring(want),
				tostring(tolerance),
				tostring(got)
			),
			0
		)
	end
end

function Context:fail(msg)
	error(msg or "falha", 0)
end

-- Troca UM campo de uma tabela de módulo e guarda o original. Restaurado AUTOMATICAMENTE no fim do
-- teste que o instalou — nunca dá para esquecer.
--
-- A tabela é a MESMA que o servidor usa. A bateria roda em Edit, mas nada impede alguém de rodá-la
-- durante um Play, e um dublê sobrevivente ali deixaria o serviço de verdade devolvendo constante,
-- sem erro nenhum no console. Restaurar por TESTE, e não por spec, também impede um dublê de vazar
-- de um teste para o seguinte — a forma mais comum de bateria verde mentir.
function Context:stub(moduleTable, field, replacement)
	if type(moduleTable) ~= "table" then
		error("stub: o primeiro argumento tem que ser a tabela do módulo", 0)
	end
	if type(moduleTable[field]) ~= "function" then
		error(
			string.format(
				"stub: '%s' não é função no módulo — nome errado (o real mudou?) ou tabela errada",
				tostring(field)
			),
			0
		)
	end
	table.insert(self._stubs, { tbl = moduleTable, field = field, original = moduleTable[field] })
	moduleTable[field] = replacement
	return moduleTable
end

function Context:stubAll(moduleTable, replacements)
	for field, fn in pairs(replacements) do
		self:stub(moduleTable, field, fn)
	end
	return moduleTable
end

-- De trás para frente: dois stubs no mesmo campo desempilham na ordem certa.
local function restoreStubs(ctx)
	for index = #ctx._stubs, 1, -1 do
		local entry = ctx._stubs[index]
		entry.tbl[entry.field] = entry.original
		ctx._stubs[index] = nil
	end
end

-- REQUIRE QUE IGNORA O CACHE DO STUDIO. Use isto, e não `require` cru, para todo módulo de produção
-- que uma spec vá exercitar.
--
-- `require` cacheia por instância de ModuleScript, e a instância vive pela sessão de Edit inteira. O
-- Rojo sincroniza o arquivo, mas quem já requereu continua com a versão antiga até o Studio
-- reiniciar. O sintoma é o pior possível: a bateria roda, fica verde (ou vermelha) sobre código que
-- não é o do disco, e a mentira convence porque o número de testes muda quando a spec muda.
--
-- O clone é instância nova, então o require compila o Source atual. Destruído na hora: o valor
-- devolvido é tabela Lua comum e sobrevive à morte do ModuleScript que a produziu. Efeito colateral
-- bom: cada spec recebe o módulo com estado zerado, então uma não contamina a seguinte.
local function requireFresh(module)
	local clone = module:Clone()
	clone.Parent = module.Parent
	local ok, result = pcall(require, clone)
	clone:Destroy()
	return ok, result
end

function Context:freshRequire(module)
	local ok, result = requireFresh(module)
	if not ok then
		error("freshRequire falhou em " .. module.Name .. ": " .. tostring(result), 0)
	end
	return result
end

local function record(ctx, name, fn, expectFailure)
	local ok, err = pcall(fn)
	-- Antes de qualquer contabilidade, e mesmo se o teste estourou.
	restoreStubs(ctx)

	local report = ctx.report
	-- Por spec, para a conferência de contagem no fim de RunAll poder acusar teste declarado que não
	-- executou. Conta os quatro desfechos: o que importa aqui é ter CHEGADO ao registro.
	report.perSpec[ctx.spec] = (report.perSpec[ctx.spec] or 0) + 1

	if expectFailure then
		if ok then
			report.fixed[#report.fixed + 1] = { spec = ctx.spec, name = name }
		else
			report.known[#report.known + 1] = { spec = ctx.spec, name = name, err = tostring(err) }
		end
		return
	end

	if ok then
		report.passed += 1
	else
		report.failed += 1
		report.failures[#report.failures + 1] = { spec = ctx.spec, name = name, err = tostring(err) }
	end
end

function Context:test(name, fn)
	record(self, name, fn, false)
end

-- Bug CONHECIDO e ainda não corrigido. Documenta o problema em código executável em vez de num
-- comentário que ninguém lê. Não quebra o relatório; se um dia PASSAR, o runner grita.
function Context:knownFailure(name, fn)
	record(self, name, fn, true)
end

-- DECLARADOS x EXECUTADOS, por spec. Trava contra o modo de falha em que a bateria MENTE PARA CIMA:
-- teste que existe no arquivo e não chega a rodar não aparece em lugar nenhum do relatório, nem
-- como falha nem como pendência, e o total continua parecendo saudável.
-- Contagem por texto de propósito: é independente do caminho de execução, então mede o arquivo em
-- vez de confiar no mesmo mecanismo que pode estar quebrado. O preço é que `t:test(` escrito dentro
-- de string ou comentário conta — não faça isso.
local function checkCounts(report)
	for _, specName in ipairs(SPEC_NAMES) do
		local module = script:FindFirstChild(specName)
		if module and module:IsA("ModuleScript") then
			local declared = 0
			for _ in module.Source:gmatch("[\r\n]%s*t:test%(") do
				declared += 1
			end
			for _ in module.Source:gmatch("[\r\n]%s*t:knownFailure%(") do
				declared += 1
			end

			local ran = report.perSpec[specName] or 0
			if declared ~= ran then
				report.failed += 1
				report.failures[#report.failures + 1] = {
					spec = specName,
					name = "(contagem de testes)",
					err = string.format(
						"%d declarado(s) no arquivo, %d executado(s). Teste declarado que não roda não "
							.. "aparece no relatório: o total fica verde por omissão. Causa provável: código "
							.. "morto na spec, ou o módulo requerido não é a versão do disco.",
						declared,
						ran
					),
				}
			end
		end
	end
end

function Tests.RunAll()
	local report = {
		passed = 0,
		failed = 0,
		failures = {},
		known = {},
		fixed = {},
		perSpec = {},
	}

	-- Bateria vazia NÃO é bateria verde. "OK, 0 passou" lido rápido vira "está coberto", que é
	-- exatamente a mentira que esta bateria existe para impedir. Enquanto não houver a primeira spec,
	-- ela reprova dizendo por quê.
	if #SPEC_NAMES == 0 then
		report.summary = "VAZIA  nenhuma spec em SPEC_NAMES — a bateria ainda não protege nada. "
			.. "A primeira correção nascida de Play vira a primeira spec."
		report.ok = false
		return report
	end

	for _, specName in ipairs(SPEC_NAMES) do
		local module = script:FindFirstChild(specName)
		if not module then
			report.failed += 1
			report.failures[#report.failures + 1] = {
				spec = specName,
				name = "(carregar spec)",
				err = "módulo não encontrado em Tests/",
			}
		else
			-- A PRÓPRIA SPEC vai por requireFresh. Com `require` cru aqui, as specs exercitariam código
			-- fresco mas viriam elas mesmas do cache do Studio: edita a spec, roda de novo na mesma
			-- sessão de Edit, e roda a versão anterior.
			local okRequire, spec = requireFresh(module)
			if not okRequire or type(spec) ~= "function" then
				report.failed += 1
				report.failures[#report.failures + 1] = {
					spec = specName,
					name = "(carregar spec)",
					err = tostring(spec),
				}
			else
				-- Erro FORA de um t:test derruba a spec inteira, não a bateria.
				local ctx = newContext(specName, report)
				local okRun, err = pcall(spec, ctx)
				-- Rede final: um stub instalado no CORPO da spec não passou por record.
				restoreStubs(ctx)
				if not okRun then
					report.failed += 1
					report.failures[#report.failures + 1] = {
						spec = specName,
						name = "(corpo da spec)",
						err = tostring(err),
					}
				end
			end
		end
	end

	checkCounts(report)

	-- Relatório legível. Falhas primeiro: é o que importa.
	local lines = {}
	for _, item in ipairs(report.failures) do
		lines[#lines + 1] = string.format("  x [%s] %s\n      %s", item.spec, item.name, item.err)
	end
	for _, item in ipairs(report.fixed) do
		lines[#lines + 1] = string.format(
			"  ^ [%s] %s\n      BUG CONHECIDO PASSOU — foi corrigido. Troque knownFailure por test.",
			item.spec,
			item.name
		)
	end
	for _, item in ipairs(report.known) do
		lines[#lines + 1] = string.format("  ! [%s] %s  (bug conhecido, ainda aberto)", item.spec, item.name)
	end

	local head = string.format(
		"%s  %d passou, %d FALHOU, %d bug(s) conhecido(s), %d corrigido(s)",
		report.failed == 0 and "OK" or "FALHOU",
		report.passed,
		report.failed,
		#report.known,
		#report.fixed
	)

	report.summary = head .. (#lines > 0 and ("\n" .. table.concat(lines, "\n")) or "")
	report.ok = report.failed == 0
	return report
end

return Tests
