-- Autogenerated with DRAKON Editor 1.32
local table = table
local string = string
local pairs = pairs
local ipairs = ipairs
local type = type
local print = print
local os = os
local tostring = tostring

local global_cfg = global_cfg

local clock = require("clock")
local log = require("log")
local digest = require("digest")
local fiber = require("fiber")

local utf8 = require("lua-utf8")

local utils = require("utils")
local ej = require("ej")
local mail = require("mail")
local trans = require("trans")

local min_user_id = 2
local max_user_id = 30
local min_email = 3
local max_email = 254
local max_pass = 100
local min_pass = 6

local db = require(global_cfg.db)

setfenv(1, {}) 

function calc_expiry()
    -- item 628
    local now = clock.time()
    local timeout = global_cfg.session_timeout
    local expires = now + timeout
    -- item 629
    return expires
end

function change_password(id_email, old_password, password)
    -- item 644
    local user = find_user(id_email)
    -- item 645
    if (user) and (old_password) then
        -- item 653
        if password then
            -- item 742
            if #password < min_pass then
                -- item 744
                return "ERR_PASSWORD_TOO_SHORT"
            else
                -- item 745
                if #password > max_pass then
                    -- item 747
                    return "ERR_PASSWORD_TOO_LONG"
                else
                    -- item 648
                    local user_id = user[1]
                    -- item 731
                    local msg = check_password(
                    	user,
                    	old_password
                    )
                    -- item 656
                    if msg then
                        -- item 897
                        log_user_event(
                        	user_id,
                        	"change_password failed",
                        	{msg = msg}
                        )
                        -- item 733
                        return msg
                    else
                        -- item 668
                        set_password_kernel(user_id, password)
                        -- item 896
                        log_user_event(
                        	user_id,
                        	"change_password",
                        	{}
                        )
                        -- item 650
                        return nil
                    end
                end
            end
        else
            -- item 655
            return "ERR_PASSWORD_EMPTY"
        end
    else
        -- item 736
        return "ERR_WRONG_PASSWORD"
    end
end

function check_logoff(session_id)
    -- item 1079
    local session = db.session_get(session_id)
    -- item 1080
    if session then
        -- item 1083
        local sdata = session[3]
        local now = clock.time()
        -- item 1084
        if now > sdata.expires then
            -- item 1078
            delete_session(session, "timeout")
        end
    end
end

function check_password(user, password)
    -- item 571
    local user_id = user[1]
    local udata = user[3]
    local now = clock.time()
    local message = nil
    -- item 572
    if udata.enabled then
        -- item 563
        local cdata = db.cred_get(user_id)
        -- item 564
        if cdata then
            -- item 725
            local valid_from = cdata.valid_from
            -- item 726
            if (valid_from) and (now < valid_from) then
                -- item 740
                message = "ERR_ACCOUNT_TEMP_DISABLED"
                -- item 730
                cdata.valid_from = 
                 now + global_cfg.password_timeout
                db.cred_upsert(user_id, cdata)
                -- item 1089
                return message
            else
                -- item 569
                local all = cdata.salt .. password
                local actual_hash = digest.sha512(all)
                -- item 570
                if actual_hash == cdata.hash then
                    -- item 568
                    return nil
                else
                    -- item 741
                    message = "ERR_WRONG_PASSWORD"
                    -- item 730
                    cdata.valid_from = 
                     now + global_cfg.password_timeout
                    db.cred_upsert(user_id, cdata)
                    -- item 1089
                    return message
                end
            end
        else
            -- item 732
            return "ERR_WRONG_PASSWORD"
        end
    else
        -- item 737
        return "ERR_ACCOUNT_DISABLED"
    end
end

function close_session(session)
    -- item 616
    delete_session(session, "logout")
end

function create_session(ip, referer, path, report)
    -- item 579
    local sdata = {
    	admin = false,
    	debug = false,
    	ip = ip,
    	user_id = "",
    	referer = referer,
    	path = path
    }
    -- item 580
    return create_session_core(
    	"",
    	sdata,
    	report
    )
end

function create_session_core(user_id, sdata, report)
    -- item 1177
    local session_id = utils.random_string()
    -- item 1178
    local expires = calc_expiry()
    -- item 1185
    sdata.expires = expires
    sdata.created = os.time()
    -- item 1180
    db.session_insert(session_id, user_id, sdata)
    -- item 1191
    if report then
        -- item 1184
        ej.info(
        	"create_session",
        	{
        		ip = ip,
        		session_id = session_id,
        		referer = referer,
        		path = path		
        	}
        )
    end
    -- item 1181
    return session_id
end

function create_user(name, email, password, session_id, reg, ip)
    -- item 332
    local result = nil
    -- item 322
    if name then
        -- item 329
        if type(name) == "string" then
            -- item 333
            if #name < min_user_id then
                -- item 325
                result = "ERR_USER_NAME_TOO_SHORT"
            else
                -- item 336
                if #name > max_user_id then
                    -- item 327
                    result = "ERR_USER_NAME_TOO_LONG"
                else
                    -- item 324
                    if email then
                        -- item 343
                        if type(email) == "string" then
                            -- item 348
                            if #email < min_email then
                                -- item 346
                                result = "ERR_EMAIL_TOO_SHORT"
                            else
                                -- item 351
                                if #email > max_email then
                                    -- item 347
                                    result = "ERR_EMAIL_TOO_LONG"
                                else
                                    -- item 354
                                    local id = name:lower()
                                    -- item 357
                                    if utils.good_id_symbols(id) then
                                        -- item 1067
                                        local ref = nil
                                        local path = nil
                                        -- item 1068
                                        if session_id then
                                            -- item 1066
                                            local session = db.session_get(session_id)
                                            -- item 1071
                                            if session then
                                                -- item 1072
                                                ref = session[3].referer
                                                path = session[3].path
                                            end
                                        end
                                        -- item 751
                                        if #password < min_pass then
                                            -- item 753
                                            return "ERR_PASSWORD_TOO_SHORT"
                                        else
                                            -- item 754
                                            if #password > max_pass then
                                                -- item 756
                                                return "ERR_PASSWORD_TOO_LONG"
                                            else
                                                -- item 376
                                                local by_id = db.user_get(id)
                                                -- item 373
                                                if by_id then
                                                    -- item 377
                                                    result = "ERR_USER_ID_NOT_UNIQUE"
                                                else
                                                    -- item 771
                                                    local space = db.space_get(id)
                                                    -- item 772
                                                    if space then
                                                        -- item 377
                                                        result = "ERR_USER_ID_NOT_UNIQUE"
                                                    else
                                                        -- item 382
                                                        email = email:lower()
                                                        -- item 381
                                                        local by_email = db.user_get_by_email(email)
                                                        -- item 378
                                                        if by_email then
                                                            -- item 380
                                                            result = "ERR_USER_EMAIL_NOT_UNIQUE"
                                                        else
                                                            -- item 383
                                                            local now = clock.time()
                                                            -- item 367
                                                            local data = {
                                                            	name = name,
                                                            	when_created = now,
                                                            	when_updated = now,
                                                            	enabled = true,
                                                            	admin = false,
                                                            	reg = reg,
                                                            	ref = ref,
                                                            	path = path,
                                                            	ip = ip
                                                            }
                                                            -- item 384
                                                            db.user_insert(id, email, data)
                                                            set_password_kernel(id, password)
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    else
                                        -- item 356
                                        result = "ERR_USER_NAME_BAD_SYMBOLS"
                                    end
                                end
                            end
                        else
                            -- item 342
                            result = "ERR_USER_NAME_NOT_STRING"
                        end
                    else
                        -- item 341
                        result = "ERR_EMAIL_EMPTY"
                    end
                end
            end
        else
            -- item 328
            result = "ERR_USER_NAME_NOT_STRING"
        end
    else
        -- item 326
        result = "ERR_USER_NAME_EMPTY"
    end
    -- item 355
    return result
end

function create_user_with_pass(user_id, email, udata, password)
    
end

function delete_session(session, reason)
    -- item 609
    local session_id = session[1]
    local user_id = session[2]
    db.session_delete(session_id)
    -- item 899
    log_user_event(
    	user_id,
    	"delete_session",
    	{
    		reason = reason,
    		session_id = session_id
    	}
    )
end

function delete_user(user_id)
    -- item 1025
    db.cred_delete(user_id)
    db.user_delete(user_id)
    -- item 1026
    log_user_event(user_id, "delete_user", {})
end

function find_user(id_email)
    -- item 1044
    if id_email then
        -- item 1049
        id_email = id_email:lower()
        -- item 1048
        local by_id = db.user_get(id_email)
        -- item 1050
        if by_id then
            -- item 1052
            return by_id
        else
            -- item 1121
            return db.user_get_by_email(id_email)
        end
    else
        -- item 1047
        return nil
    end
end

function find_users(data)
    -- item 837
    local crit = utf8.lower(data.text)
    crit = utils.trim(crit)
    -- item 832
    local found = {}
    -- item 1137
    local users = db.user_get_all()
    for _, user in ipairs(users) do
        -- item 834
        local user_id = user[1]
        local udata = user[3]
        local name = udata.name
        -- item 838
        if user_id:match(crit) then
            -- item 841
            table.insert(
            	found,
            	name
            )
        end
    end
    -- item 833
    return {
    	found = found
    }
end

function force_logout(user_id, time)
    -- item 1101
    local count = 0
    -- item 1095
    local user_sessions = db.session_get_by_user(user_id)
    for _, session in ipairs(user_sessions) do
        -- item 1099
        local session_id = session[1]
        local user_id = session[2]
        local sdata = session[3]
        -- item 1103
        if (sdata.created) and (not (sdata.created < time)) then
            
        else
            -- item 1100
            db.session_delete(session_id)
            count = count + 1
        end
    end
    -- item 1102
    return count
end

function force_logout_all_users(time)
    -- item 1111
    local count = 0
    -- item 1139
    local users = db.user_get_all()
    for _, user in ipairs(users) do
        -- item 1115
        local user_id = row[1]
        -- item 1118
        count = count + force_logout(user_id, time)
    end
    -- item 1112
    return count
end

function get_config()
    -- item 585
    return {
    	SESSION_TIMEOUT = 60 * 4
    }
end

function get_create_session(session_id, ip, referer, path, report)
    -- item 423
    local result = { 
    	admin = false,
    	user_id = "",
    	name = "",
    	debug = false
    }
    -- item 417
    if session_id then
        -- item 410
        local session = db.session_get(session_id)
        -- item 411
        if session then
            -- item 1162
            local sdata = session[3]
            local expires = sdata.expires
            -- item 1153
            if clock.time() > expires then
                -- item 1166
                db.session_delete(
                	session_id
                )
                -- item 1190
                report = false
                -- item 408
                session_id = create_session(
                	ip,
                	referer,
                	path,
                	report
                )
            else
                -- item 1157
                result.user_id = session[2]
                result.admin = sdata.admin
                result.name = sdata.name
                result.debug = not not sdata.debug
            end
        else
            -- item 408
            session_id = create_session(
            	ip,
            	referer,
            	path,
            	report
            )
        end
    else
        -- item 408
        session_id = create_session(
        	ip,
        	referer,
        	path,
        	report
        )
    end
    -- item 409
    result.session_id = session_id
    -- item 407
    return result
end

function get_or_create_usecret(user_id)
    -- item 964
    return nil
end

function get_unsubscribe_code(user_id)
    -- item 1194
    return nil
end

function get_user(user_id)
    -- item 687
    if user_id then
        -- item 677
        local user = db.user_get(user_id)
        -- item 678
        if user then
            -- item 681
            local email = user[2]
            local udata = user[3]
            -- item 826
            local result = {
            	user_id = user_id,
            	email = email,
            	block_email = udata.block_email,
            	name = udata.name,
            	admin = udata.admin,
            	enabled = udata.enabled,
            	debug = udata.debug,
            	max_spaces = udata.max_spaces,
            	license = udata.license,
            	had_trial = udata.had_trial or false
            }
            -- item 684
            return result
        else
            -- item 683
            return nil
        end
    else
        -- item 683
        return nil
    end
end

function get_user_data(user_id)
    -- item 791
    if user_id then
        -- item 783
        local user = db.user_get(user_id)
        -- item 784
        if user then
            -- item 787
            local udata = user[3]
            -- item 790
            return udata
        else
            -- item 789
            return nil
        end
    else
        -- item 789
        return nil
    end
end

function hello(value)
    -- item 466
    return value * 5
end

function log_user_event(user_id, type, data)
    -- item 894
    data.user_id = user_id
    -- item 895
    ej.info(type, data)
end

function logon(session_id, id_email, password)
    -- item 454
    if session_id then
        -- item 453
        local session = db.session_get(session_id)
        -- item 456
        if session then
            -- item 449
            local user = find_user(id_email)
            -- item 450
            if user then
                -- item 734
                local msg = check_password(
                	user,
                	password
                )
                -- item 457
                if msg then
                    -- item 901
                    ej.info(
                    	"logon failed",
                    	{
                    		session_id = session_id,
                    		msg = msg,
                    		id_email = id_email
                    	}
                    )
                    -- item 735
                    return false, msg
                else
                    -- item 459
                    local sdata = session[3]
                    local user_id = user[1]
                    local email = user[2]
                    local udata = user[3]
                    -- item 1167
                    local new_session = reset_session(
                    	session_id,
                    	sdata,
                    	user_id,
                    	email,
                    	udata
                    )
                    -- item 900
                    log_user_event(
                    	user_id,
                    	"logon",
                    	{session_id = session_id}
                    )
                    -- item 685
                    return true, udata.name, user_id, email,
                    	new_session
                end
            else
                -- item 902
                ej.info(
                	"logon - wrong password",
                	{
                		session_id = session_id,
                		id_email = id_email
                	}
                )
                -- item 686
                return false, "ERR_WRONG_PASSWORD"
            end
        else
            -- item 902
            ej.info(
            	"logon - wrong password",
            	{
            		session_id = session_id,
            		id_email = id_email
            	}
            )
            -- item 686
            return false, "ERR_WRONG_PASSWORD"
        end
    else
        -- item 902
        ej.info(
        	"logon - wrong password",
        	{
        		session_id = session_id,
        		id_email = id_email
        	}
        )
        -- item 686
        return false, "ERR_WRONG_PASSWORD"
    end
end

function logout(session_id)
    -- item 430
    if session_id then
        -- item 433
        local this_session = db.session_get(session_id)
        -- item 435
        if this_session then
            -- item 436
            local user_id = this_session[2]
            -- item 437
            if user_id == "" then
                -- item 439
                close_session(this_session)
            else
                -- item 1036
                logout_all(user_id)
            end
        end
    end
end

function logout_all(user_id)
    -- item 1032
    local user_sessions = db.session_get_by_user(user_id)
    for _, session in ipairs(user_sessions) do
        -- item 1035
        close_session(session)
    end
end

function make_cred(password)
    -- item 556
    local salt = digest.urandom(64)
    local all = salt .. password
    local hash = digest.sha512(all)
    -- item 557
    return {
    	salt = salt,
    	hash = hash
    }
end

function refresh_session(session)
    -- item 623
    local session_id
    local user_id
    local sdata
    session_id, user_id, sdata = session:unpack()
    sdata.expires = calc_expiry()
    -- item 1119
    db.session_update(session_id, user_id, sdata)
end

function reset_password(id_email, session_id, language)
    -- item 876
    local user = find_user(id_email)
    -- item 877
    if user then
        -- item 888
        local password = utils.random_string()
        password = password:sub(1, 8)
        -- item 880
        local id = user[1]
        local email = user[2]
        -- item 883
        set_password_kernel(id, password)
        -- item 903
        log_user_event(
        	id,
        	"reset_password",
        	{session_id=session_id}
        )
        -- item 907
        send_pass_reset_email(
        	id,
        	email,
        	password,
        	language
        )
        -- item 882
        return true, {}
    else
        -- item 904
        ej.info(
        	"reset_password fail",
        	{id_email = id_email, session_id=session_id}
        )
        -- item 881
        return false, "ERR_USER_NOT_FOUND"
    end
end

function reset_session(old_session_id, sdata, user_id, email, udata)
    -- item 1173
    db.session_delete(
    	old_session_id
    )
    -- item 1187
    sdata.email = email
    sdata.user_id = user_id
    sdata.admin = not not udata.admin
    sdata.name = udata.name
    sdata.expires = calc_expiry()
    -- item 1188
    return create_session_core(
    	user_id,
    	sdata,
    	false
    )
end

function send_pass_reset_email(user_id, email, password, language)
    -- item 913
    local htmlRaw = mail.get_template(
    	language,
    	"reset.html"
    )
    -- item 914
    local textRaw = mail.get_template(
    	language,
    	"reset.txt"
    )
    -- item 915
    local html = htmlRaw:gsub("USER_PASSWORD", password)
    html = html:gsub("USER_NAME", user_id)
    -- item 916
    local text = textRaw:gsub("USER_PASSWORD", password)
    text = text:gsub("USER_NAME", user_id)
    -- item 919
    local subject = trans.translate(
    	language,
    	"index",
    	"MES_RESET_DONE"
    )
    -- item 918
    mail.send_mail(
    	user_id,
    	email,
    	subject,
    	text,
    	html,
    	nil
    )
end

function set_debug(user_id, debug)
    -- item 1136
    set_user_prop(
    	user_id,
    	"debug",
    	debug
    )
end

function set_password(admin_id, id_email, password)
    -- item 390
    local user = find_user(id_email)
    -- item 391
    if user then
        -- item 399
        if password then
            -- item 394
            local id = user[1]
            -- item 397
            set_password_kernel(id, password)
            -- item 905
            log_user_event(
            	admin_id,
            	"set_password",
            	{principal = id}
            )
            -- item 396
            return nil
        else
            -- item 401
            return "ERR_PASSWORD_EMPTY"
        end
    else
        -- item 395
        return "ERR_USER_NOT_FOUND"
    end
end

function set_password_kernel(user_id, password)
    -- item 666
    local cred = make_cred(password)
    -- item 667
    db.cred_upsert(user_id, cred)
end

function set_session_ref(session_id, ref)
    -- item 1062
    local session = db.session_get(session_id)
    -- item 1063
    if session then
        -- item 1061
        local session_id
        local user_id
        local sdata
        session_id, user_id, sdata = session:unpack()
        sdata.referer = ref
        -- item 1120
        db.session_update(session_id, user_id, sdata)
    end
end

function set_user_prop(user_id, name, value)
    -- item 864
    local user = db.user_get(user_id)
    -- item 865
    if user then
        -- item 868
        local email = user[2]
        local udata = user[3]
        -- item 869
        udata[name] = value
        -- item 870
        db.user_update(
        	user_id,
        	email,
        	udata
        )
    end
end

function unsubscribe(data)
    
end

function update_user(user_id, data)
    -- item 701
    if user_id then
        -- item 693
        local user = db.user_get(user_id)
        -- item 694
        if user then
            -- item 705
            local email = data.email
            -- item 703
            if (email) and (not (#email < min_email)) then
                -- item 709
                if #email > max_email then
                    -- item 708
                    return "ERR_EMAIL_TOO_LONG"
                else
                    -- item 711
                    email = email:lower()
                    -- item 1122
                    local by_email = db.user_get_by_email(email)
                    -- item 717
                    if (by_email) and (not (by_email[1] == user_id)) then
                        -- item 713
                        return "ERR_USER_EMAIL_NOT_UNIQUE"
                    else
                        -- item 697
                        local udata = user[3]
                        udata.when_updated = clock.time()
                        udata.block_email = data.block_email
                        -- item 698
                        db.user_update(
                        	user_id,
                        	email,
                        	udata
                        )
                        -- item 906
                        log_user_event(
                        	user_id,
                        	"update_user",
                        	{}
                        )
                        -- item 699
                        return nil
                    end
                end
            else
                -- item 706
                return "ERR_EMAIL_TOO_SHORT"
            end
        else
            -- item 702
            return "ERR_USER_NOT_FOUND"
        end
    else
        -- item 702
        return "ERR_USER_NOT_FOUND"
    end
end


return {
	hello = hello,
	create_user = create_user,
	set_password = set_password,
	change_password = change_password,
	logon = logon,
	logout = logout,
	get_create_session = get_create_session,
	get_user = get_user,
	update_user = update_user,
	find_users = find_users,
	set_debug = set_debug,
	set_user_prop = set_user_prop,
	reset_password = reset_password,
	unsubscribe = unsubscribe,
	get_unsubscribe_code = get_unsubscribe_code,
	delete_user = delete_user,
	logout_all = logout_all,
	find_user = find_user,
	set_session_ref = set_session_ref,
	check_logoff = check_logoff,
	force_logout_all_users = force_logout_all_users
}