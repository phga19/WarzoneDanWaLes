require 'version';
require '_ui';
require '_settings';
require '_util';
require 'cards';

local rootParent = nil;
local game = nil;
local mainVert = nil;
local stored = nil;

function Client_PresentMenuUI(_rootParent, setMaxSize, setScrollable, _game, close)
	game = _game;

	if not game.Us or game.Us.State ~= WL.GamePlayerState.Playing then
		return;
	end

	if hasNoCardsEnabled() or not canRunMod() then
		return;
	end

	setMaxSize(400, 300);

	rootParent = _rootParent;
	main({
		PlayerGameData = Mod.PlayerGameData,
		PublicGameData = Mod.PublicGameData
	}, 1);
end

function hasNoCardsEnabled()
	for _, cardName in pairs(Mod.PublicGameData.cardNames) do
		if getSetting('Enable' .. cardName) then
			return false;
		end
	end

	return true;
end

function main(_stored, i)
	if not UI.IsDestroyed(mainVert) then
		UI.Destroy(mainVert);
	end
	mainVert = Vert(rootParent);

	stored = _stored;

	local tabs = {'Cards', 'Preferences'};
	local clicks = {cardsClicked, preferencesClicked}
	local tabData = Tabs(mainVert, Horz, tabs, clicks);
	tabData.tabClicked(tabs[i], clicks[i]);
end

function cardsClicked(tabData)
	local tabs = {};
	for _, cardName in pairs(Mod.PublicGameData.cardNames) do
		if getSetting('Enable' .. cardName) then
			table.insert(tabs, cardName);
		end
	end

	local clicks = {};
	for _, cardName in pairs(tabs) do
		table.insert(clicks, function(tabData2)
			cardNameClicked(tabData2, cardName);
		end);
	end

	local tabData2 = Tabs(tabData.tabContents, Vert, tabs, clicks);
	tabData2.tabClicked(tabs[1], clicks[1]);
end

function cardNameClicked(tabData, cardName)
	-- cant know for sure how much cards each player has used

	local piecesInCard = getSetting(cardName .. 'PiecesInCard');
	local teamType = game.Us.Team == -1 and 'noTeam' or 'teammed';
	local teamId = game.Us.Team == -1 and game.Us.ID or game.Us.Team;
	local myPieces = Mod.PublicGameData.cardPieces[teamType][teamId].currentPieces[cardName];
	local wholeCards = math.floor(myPieces / piecesInCard);

	Label(tabData.tabContents).SetText('Whole cards: ' .. wholeCards);
	Label(tabData.tabContents).SetText('Pieces: ' .. (myPieces % piecesInCard) .. '/' .. piecesInCard);

	local btn = Btn(tabData.tabContents).SetText('Use card');
	local vert = Vert(tabData.tabContents);

	if game.Game.State == WL.GameState.Playing then
		btn.SetInteractable(wholeCards > 0);
	else
		btn.SetInteractable(false);
	end

	btn.SetOnClick(function()
		_G['playCard' .. string.gsub(cardName, '[^%w_]', '')](game, tabData, cardName, btn, vert, nil, {});
	end);

	local isBuyable = getSetting(cardName .. 'IsBuyable') and game.Settings.CommerceGame;

	if isBuyable then
		local cost = getSetting(cardName .. 'Cost');
		local btn = Btn(tabData.tabContents);

		btn.SetText('Buy a whole card for ' .. cost .. ' gold');
		btn.SetOnClick(function()
			local msg = 'Buy a ' .. cardName .. ' Card';
			local payload = 'CCP2_buyCard_' .. game.Us.ID .. '_<' .. cardName .. '=[]>';
			local costOpt = {[WL.ResourceType.Gold] = cost};
			local order = WL.GameOrderCustom.Create(game.Us.ID, msg, payload, costOpt, WL.TurnPhase.Purchase);

			placeOrderInCorrectPosition(game, order);
		end);

		if game.Game.State ~= WL.GameState.Playing then
			btn.SetInteractable(false);
		end
	end
end

function createDoneAndCancelForCardUse(game, tabData, cardName, parent, playerId, calcOrderDetails);
	local horz = Horz(parent);
	local doneBtn = Btn(horz);
	local cancelBtn = Btn(horz);

	doneBtn.SetText('Done');
	doneBtn.SetOnClick(function()
		local orderDetails = calcOrderDetails();

		if not orderDetails then
			return;
		end

		local fullmsg = 'Play ' .. cardName .. ' Card' .. (orderDetails.msg or '');
		local payload = 'CCP2_playedCard_' .. playerId .. '_<' .. cardName .. '=[' .. (orderDetails.param or '') .. ']>';
		local order = WL.GameOrderCustom.Create(playerId, fullmsg, payload, nil, orderDetails.phase);

		placeOrderInCorrectPosition(game, order);
		tabData.clickTab(cardName);
	end);

	cancelBtn.SetText('Cancel');
	cancelBtn.SetOnClick(function()
		tabData.clickTab(cardName);
	end);
end

function createTerritorySelectionCard(game, tabData, cardName, btn, vert, vert2, data)
	btn.SetInteractable(false);

	if not UI.IsDestroyed(vert2) then
		UI.Destroy(vert2);
	end

	local vert2 = Vert(vert);
	local errMsg = nil;

	Label(vert2).SetText('Select a territory that you want to play a ' .. cardName .. ' Card on');
	createSelectTerritoryMenu(vert2, data.selectedTerr, function(selectedTerr)
		if data.validateTerrSelection(selectedTerr) then
			errMsg.SetText('');
			data.selectedTerr = selectedTerr;
			createTerritorySelectionCard(game, tabData, cardName, btn, vert, vert2, data);
		else
			errMsg.SetText(data.errMsg);
		end
	end);

	errMsg = Label(vert2).SetColor('#FF0000');

	createDoneAndCancelForCardUse(game, tabData, cardName, vert2, game.Us.ID, function()
		if not data.selectedTerr then
			return;
		end

		return {
			msg = ' on ' .. data.selectedTerr.Name,
			param = data.selectedTerr.ID,
			phase = data.phase
		};
	end);
end

function createSelectTerritoryMenu(parent, selectedTerr, newTerrSelectedCallback)
	local selectTerritoryHorz = Horz(parent);
	local label = Label(selectTerritoryHorz).SetText('Selected: ');
	local selectTerritoryBtn = Btn(selectTerritoryHorz);
	selectTerritoryBtn.SetText(selectedTerr and selectedTerr.Name or 'None');
	selectTerritoryBtn.SetOnClick(function()
		label.SetText('');
		selectTerritoryBtn.SetText('(Selecting)');
		selectTerritoryBtn.SetInteractable(false);

		local isCanceled = false;
		local cancelBtn = Btn(selectTerritoryHorz);
		cancelBtn.SetText('Cancel');
		cancelBtn.SetOnClick(function()
			isCanceled = true;
			UI.Destroy(cancelBtn);
			selectTerritoryBtn.SetText(selectedTerr and selectedTerr.Name or 'None');
			selectTerritoryBtn.SetInteractable(true);
		end);

		UI.InterceptNextTerritoryClick(function(terrDetails)
			if isCanceled then
				return WL.CancelClickIntercept;
			end

			if not UI.IsDestroyed(cancelBtn) then
				UI.Destroy(cancelBtn);
			end

			label.SetText('Selected: ');
			selectTerritoryBtn.SetText(terrDetails and terrDetails.Name or 'None');
			selectTerritoryBtn.SetInteractable(true);
			newTerrSelectedCallback(terrDetails);
		end);
	end);
end

Dropdowns = {
	list = {},-- so that incorrect schematics arent used
	selectedClicked = function(dropdownIndex)
		local dd = Dropdowns.list[dropdownIndex];

		if type(dd.labels) ~= 'table' then
			return;
		end

		dd.label.SetText('');
		dd.selected.SetText('(Selecting)');
		dd.selected.SetInteractable(false);
		dd.cancelBtn = Btn(dd.horz);
		dd.cancelBtn.SetText('Cancel');
		dd.cancelBtn.SetOnClick(function()
			Dropdowns.optionClicked(dropdownIndex);
		end);

		if not UI.IsDestroyed(dd.vert2) then
			UI.Destroy(dd.vert2);
		end

		Dropdowns.list[dropdownIndex].vert2 = Vert(dd.vert);

		for i, label in ipairs(dd.labels) do
			local option = Btn(Dropdowns.list[dropdownIndex].vert2);

			option.SetText(label);
			option.SetFlexibleWidth(1);
			option.SetOnClick(function()
				Dropdowns.optionClicked(dropdownIndex, i);
			end);
		end
	end,
	optionClicked = function(dropdownIndex, i)
		local dd = Dropdowns.list[dropdownIndex];

		if i then
			Dropdowns.list[dropdownIndex].selectedOptionNo = i;
			dd.onOptionClicked(i);
		else
			i = dd.selectedOptionNo;
		end

		if not UI.IsDestroyed(dd.cancelBtn) then
			UI.Destroy(dd.cancelBtn);
		end

		if not UI.IsDestroyed(dd.vert2) then
			UI.Destroy(dd.vert2);
		end

		dd.label.SetText('Selected: ');
		dd.selected.SetText(i and dd.labels[i] or 'None');
		dd.selected.SetInteractable(true);
	end,
	create = function(parent, labelTxt, selectedOptionNo, labels, onOptionClicked)
		local index = #Dropdowns.list + 1;
		local heading = Label(parent).SetText(labelTxt);
		local horz = Horz(parent);
		local label = Label(horz).SetText('Selected: ');
		local selected = Btn(horz);
		local vert = Vert(parent);

		table.insert(Dropdowns.list, {
			selectedOptionNo = selectedOptionNo,
			labels = labels,
			onOptionClicked = onOptionClicked,
			heading = heading,
			horz = horz,
			label = label,
			selected = selected,
			cancelBtn = nil,
			vert = vert,
			vert2 = nil
		});

		local dd = Dropdowns.list[index];
		dd.selected.SetOnClick(function()
			Dropdowns.selectedClicked(index);
		end)

		Dropdowns.optionClicked(index, dd.selectedOptionNo);
	end
}

function preferencesClicked(tabData)
	local preferences = {
		prefShowReceivedCardsMsg = 'Show received cards dialog'
	};

	for pref, label in pairs(preferences) do
		Label(tabData.tabContents).SetText(label .. ': ');
		local btn = Btn(tabData.tabContents);
		btn.SetText(tostring(stored.PlayerGameData[pref]))
		btn.SetOnClick(function()
			btn.SetInteractable(false);

			game.SendGameCustomMessage('Updating preferences...', {
				PlayerGameData = {
					[pref] = not stored.PlayerGameData[pref]
				}
			}, function(_stored)
				main(_stored, 2);
			end);
		end);
	end
end