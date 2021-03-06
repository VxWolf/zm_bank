function BaseInteractionExt:selected(player, locator, hand_id)
	if not self:can_select(player) then
		return
	end

	self._hand_id = hand_id
	self._is_selected = true
	local string_macros = {}

	self:_add_string_macros(string_macros)

	local text = ""

	if self._tweak_data.zm_interaction then
		text = "Hold " .. managers.localization:btn_macro("interact") .. " to buy"

		if self._tweak_data.weapon then
			local current_money = managers.wdu:_get_own_money()
			local cost = self._tweak_data.points_cost or 0
			local item = self._tweak_data.weapon

			if current_money >= cost then
				text = text .. " the " .. item
				text = text .. " [Cost : " .. cost .. "]"
			else
				local points_needed = cost - current_money
				text = "You need " .. points_needed .. " more points to buy the " .. item
			end
		end

	else
		local text_id = self._tweak_data.text_id or alive(self._unit) and self._unit:base().interaction_text_id and self._unit:base():interaction_text_id()
		text = managers.localization:text(text_id, string_macros)
		local icon = self._tweak_data.icon

		if self._tweak_data.special_equipment and not managers.player:has_special_equipment(self._tweak_data.special_equipment) then
			local has_special_equipment = false
	
			if self._tweak_data.possible_special_equipment then
				for i, special_equipment in ipairs(self._tweak_data.possible_special_equipment) do
					if managers.player:has_special_equipment(special_equipment) then
						has_special_equipment = true
	
						break
					end
				end
			end
	
			if not has_special_equipment then
				text = managers.localization:text(self._tweak_data.equipment_text_id, string_macros)
				icon = self.no_equipment_icon or self._tweak_data.no_equipment_icon or icon
			end
		end
	
		if self._tweak_data.contour_preset or self._tweak_data.contour_preset_selected then
			if not self._selected_contour_id and self._tweak_data.contour_preset_selected and self._tweak_data.contour_preset ~= self._tweak_data.contour_preset_selected then
				self._selected_contour_id = self._unit:contour():add(self._tweak_data.contour_preset_selected)
			end
		else
			self:set_contour("selected_color")
		end
	end

	managers.hud:show_interact({
		text = text,
		icon = icon
	})

	return true
end

function BaseInteractionExt:can_interact(player)
	if self._host_only and not Network:is_server() then
		return false
	end

	if self._disabled then
		return false
    end
    
    local count_perks = managers.player:_count_nb_perks()
	local max_perks = 4
	
	if self._tweak_data.is_teleporter and not managers.wdu:_is_teleporter_available() then
		return false
	end

    if self._tweak_data.is_perk_interaction and count_perks >= max_perks then
        return false
	end
	
	if self._tweak_data.zm_interaction then
		local current_money = managers.wdu:_get_own_money()
		local cost = self._tweak_data.points_cost or 0

		if current_money < cost then
			return false
		end
	end

	if not self:_has_required_upgrade(alive(player) and player:movement() and player:movement().current_state_name and player:movement():current_state_name()) then
		return false
	end

	if not self:_has_required_deployable() then
		return false
	end

	if not self:_is_in_required_state(alive(player) and player:movement() and player:movement().current_state_name and player:movement():current_state_name()) then
		return false
	end

	if self._tweak_data.special_equipment_block and managers.player:has_special_equipment(self._tweak_data.special_equipment_block) then
		return false
	end

	if not self._tweak_data.special_equipment or self._tweak_data.dont_need_equipment then
		return true
	end

	return managers.player:has_special_equipment(self._tweak_data.special_equipment)
end

function BaseInteractionExt:_get_timer()
	local modified_timer = self:_get_modified_timer()

	if modified_timer then
		return modified_timer
	end

	local multiplier = 1

	if self.tweak_data ~= "corpse_alarm_pager" then
		multiplier = multiplier * managers.player:crew_ability_upgrade_value("crew_interact", 1)
	end

	if self._tweak_data.upgrade_timer_multiplier then
		multiplier = multiplier * managers.player:upgrade_value(self._tweak_data.upgrade_timer_multiplier.category, self._tweak_data.upgrade_timer_multiplier.upgrade, 1)
	end

	if self._tweak_data.upgrade_timer_multipliers then
		for _, upgrade_timer_multiplier in pairs(self._tweak_data.upgrade_timer_multipliers) do
			multiplier = multiplier * managers.player:upgrade_value(upgrade_timer_multiplier.category, upgrade_timer_multiplier.upgrade, 1)
		end
	end

	if managers.player:has_category_upgrade("player", "level_interaction_timer_multiplier") then
		local data = managers.player:upgrade_value("player", "level_interaction_timer_multiplier") or {}
		local player_level = managers.experience:current_level() or 0
		multiplier = multiplier * (1 - (data[1] or 0) * math.ceil(player_level / (data[2] or 1)))
	end

	if self.tweak_data == "revive" then
		if managers.player:has_special_equipment("perk_quickrevive") then
			multiplier = multiplier * 2
		end
	end

	return self:_timer_value() * multiplier * managers.player:toolset_value()
end

function BaseInteractionExt:interact(player)
	self._tweak_data_at_interact_start = nil

	if self._tweak_data.zm_interaction then
		local amount_to_deduct = self._tweak_data.points_cost
		managers.wdu:_deduct_money_to(managers.wdu:_peer_id(), amount_to_deduct)
	end

	self:_post_event(player, "sound_done")
end

function BaseInteractionExt:set_active(active, sync)
	if active and self:disabled() then
		return
	end

	if self._tweak_data.stay_active then
		active = true
	end

	if self._host_only and not Network:is_server() then
		active = false
	end

	if not active and self._active then
		managers.interaction:remove_unit(self._unit)

		if self._tweak_data.contour_preset or self._tweak_data.contour_preset_selected then
			if self._contour_id and self._unit:contour() then
				self._unit:contour():remove_by_id(self._contour_id)
			end

			self._contour_id = nil

			if self._selected_contour_id and self._unit:contour() then
				self._unit:contour():remove_by_id(self._selected_contour_id)
			end

			self._selected_contour_id = nil
		elseif not self._tweak_data.no_contour then
			managers.occlusion:add_occlusion(self._unit)
		end

		self._is_selected = nil
	elseif active and not self._active then
		managers.interaction:add_unit(self._unit)

		if self._tweak_data.contour_preset then
			if not self._contour_id then
				self._contour_id = self._unit:contour():add(self._tweak_data.contour_preset)
			end
		elseif not self._tweak_data.no_contour then
			managers.occlusion:remove_occlusion(self._unit)
		end
	end

	self._active = active

	if not self._tweak_data.contour_preset then
		local opacity_value = self:_set_active_contour_opacity()

		self:set_contour("standard_color", opacity_value)
	end

	if not self._host_only and sync and managers.network:session() then
		local u_id = self._unit:id()

		if u_id == -1 then
			local u_data = managers.enemy:get_corpse_unit_data_from_key(self._unit:key())

			if u_data then
				u_id = u_data.u_id
			else
				debug_pause_unit(self._unit, "[BaseInteractionExt:set_active] could not sync interaction state.", self._unit)

				return
			end
		end

		managers.network:session():send_to_peers_synched("interaction_set_active", self._unit, u_id, active, self.tweak_data, self._unit:contour() and self._unit:contour():is_flashing() or false)
	end
end

function UseInteractionExt:sync_interacted(peer, player, status, skip_alive_check)
	if not self._active then
		return
	end

	if self._tweak_data.zm_interaction then
		local amount_to_deduct = self._tweak_data.points_cost
		managers.wdu:_deduct_money_to(peer, amount_to_deduct)

		if not self._tweak_data.stay_active then
			self:remove_interact()
			self:set_active(false)
		end
	else
		local player = peer:unit()

		if not skip_alive_check and not alive(player) then
			return
		end

		if player ~= managers.player:player_unit() then
			if self._achievement_stat then
				managers.achievment:award_progress(self._achievement_stat)
			elseif self._achievement_id then
				managers.achievment:award(self._achievement_id)
			elseif self._challenge_stat then
				managers.challenge:award_progress(self._challenge_stat)
			elseif self._trophy_stat then
				managers.custom_safehouse:award(self._trophy_stat)
			elseif self._challenge_award then
				managers.challenge:award(self._challenge_award)
			elseif self._sidejob_award then
				managers.generic_side_jobs:award(self._sidejob_award)
			elseif self.award_blackmarket then
				local args = string.split(self.award_blackmarket, " ")

				managers.blackmarket:add_to_inventory(unpack(args))
			end
		end

		self:remove_interact()
		self:set_active(false)
	end

	if self._unit:damage() then
		self._unit:damage():run_sequence_simple("interact", {unit = player})
	end

	return player
end