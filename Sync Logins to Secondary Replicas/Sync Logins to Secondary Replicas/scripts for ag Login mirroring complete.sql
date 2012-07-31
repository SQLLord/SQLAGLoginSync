USE master
GO
IF OBJECT_ID ('sp_hexadecimal') IS NOT NULL
  DROP PROCEDURE sp_hexadecimal
  GO
  CREATE PROCEDURE sp_hexadecimal
@binvalue varbinary(256),
@hexvalue varchar (514) OUTPUT
AS
DECLARE @charvalue varchar (514)
DECLARE @i int
DECLARE @length int
DECLARE @hexstring char(16)
SELECT @charvalue = '0x'
SELECT @i = 1
SELECT @length = DATALENGTH (@binvalue)
 SELECT @hexstring = '0123456789ABCDEF'
 WHILE (@i <= @length)
 BEGIN
 DECLARE @tempint int
 DECLARE @firstint int
 DECLARE @secondint int
 SELECT @tempint = CONVERT(int, SUBSTRING(@binvalue,@i,1))
 SELECT @firstint = FLOOR(@tempint/16)
 SELECT @secondint = @tempint - (@firstint*16)
 SELECT @charvalue = @charvalue +
 SUBSTRING(@hexstring, @firstint+1, 1) +
 SUBSTRING(@hexstring, @secondint+1, 1)
 SELECT @i = @i + 1
 END

SELECT @hexvalue = @charvalue
GO 
IF OBJECT_ID ('usp_get_list_of_AG_Logins') IS NOT NULL
DROP PROCEDURE usp_get_list_of_AG_Logins
GO


create procedure usp_get_list_of_AG_Logins 
@Listenername nvarchar(63)
as
Begin

----Script to gather login info and prep for loading in secondary servers---------
----------------------------------------------------------------------------------


-----create temp table to store login and replica info----------------------------
----------------------------------------------------------------------------------


/****** Object:  Table [dbo].[testtable]    Script Date: 7/26/2012 3:46:10 PM ******/

CREATE TABLE #replicadbs (
	[useridcounter] [int] IDENTITY(1,1) NOT NULL,
	[agname] [sysname] NULL,
	[database_name] [sysname] NULL,
	[replica_server_name] [nvarchar](256) NULL,
	[role_desc] [nvarchar](60) NULL,
	[connected_state] [tinyint] NULL
) ON [PRIMARY]




---------load list of secondary servers and which dbs are mirroring to them using Always ON-------
---------------------------------------------------------------------------------------------------

insert into #replicadbs
(agname,database_name,replica_server_name,role_desc,connected_state)
select 
d.name as agname,
c.database_name,
b.replica_server_name,
a.role_desc,
a.connected_state
 from 
sys.dm_hadr_availability_replica_states as a
join sys.availability_replicas as b 
on a.replica_id = b.replica_id
join sys.availability_databases_cluster as c
on a.group_id = c.group_id
join sys.availability_groups as d on 
a.group_id = d.group_id
join sys.availability_group_listeners as e
on a.group_id = e.group_id
where a.role_desc = 'Secondary'
and a.connected_state = 1
and e.dns_name = @Listenername


-----------create table with replica and db and user info-------------
---------------------------------------------------------------------


CREATE TABLE #replicadbusers (
	[useridcounter] [int] IDENTITY(1,1) NOT NULL,
	[agname] [sysname] NULL,
	[database_name] [sysname] NULL,
	[replica_server_name] [nvarchar](256) NULL,
	[role_desc] [nvarchar](60) NULL,
	[connected_state] [tinyint] NULL,
	[dbusername] [sysname] NULL,
	[loginname] [sysname] NULL,
	[adduserlogincommand] varchar(max) NULL,
	[SID_string] varchar (514) NULL,
	[LoginType] char(1) NULL
) ON [PRIMARY]


-----use cursor to list all users for each db that logins must be synced over with--------
------------------------------------------------------------------------------------------



SET NOCOUNT ON;

DECLARE 
@agname [sysname] ,
	@database_name [sysname] ,
	@replica_server_name [nvarchar](256) ,
	@role_desc [nvarchar](60) ,
	@connected_state [tinyint],
	@selectcommand varchar(max) 


	DECLARE replicadbs CURSOR FOR 
	SELECT agname,database_name,replica_server_name,role_desc,connected_state from #replicadbs

	OPEN replicadbs

	FETCH NEXT FROM replicadbs 
	INTO @agname, @database_name, @replica_server_name, @role_desc, @connected_state

	WHILE @@FETCH_STATUS = 0
	BEGIN
	   

select @selectcommand = 'insert into #replicadbusers (agname,database_name,replica_server_name,role_desc,connected_state,dbusername,loginname) select ''' + convert(varchar,@agname) + ''', ''' + convert(varchar,@database_name) + ''', ''' + convert(varchar,@replica_server_name) + ''', ''' + convert(varchar,@role_desc) + ''', ' + convert(varchar,@connected_state) + ',  a.name, b.loginname from ' + convert(varchar,@database_name) + '.sys.sysusers as a join sys.syslogins as b on a.sid = b.sid'
execute (@selectcommand)


      -- Get the next vendor.
    FETCH NEXT FROM replicadbs 
  INTO @agname, @database_name, @replica_server_name, @role_desc, @connected_state
END 
CLOSE replicadbs;
DEALLOCATE replicadbs;


------use cursor so we can get the login script build from sp_rev_login---------------
---------------------------------------------------------------------------------------


declare @login_name sysname 
DECLARE @name sysname
DECLARE @type varchar (1)
DECLARE @hasaccess int
DECLARE @denylogin int
DECLARE @is_disabled int
DECLARE @PWD_varbinary  varbinary (256)
DECLARE @PWD_string  varchar (514)
DECLARE @SID_varbinary varbinary (85)
DECLARE @SID_string varchar (514)
DECLARE @tmpstr  varchar (1024)
DECLARE @is_policy_checked varchar (3)
DECLARE @is_expiration_checked varchar (3)
declare @useridcounter int
declare @loginType char(1)

DECLARE @defaultdb sysname
declare loginscursor cursor for 
select useridcounter, loginname from #replicadbusers

	OPEN loginscursor

	FETCH NEXT FROM loginscursor 
	INTO @useridcounter, @login_name

			WHILE @@FETCH_STATUS = 0
			BEGIN


 
					 IF (@login_name IS NULL)
					   DECLARE login_curs CURSOR FOR

					 SELECT p.sid, p.name, p.type, p.is_disabled, p.default_database_name, l.hasaccess, l.denylogin FROM 
					 sys.server_principals p LEFT JOIN sys.syslogins l
					 ON ( l.name = p.name ) WHERE p.type IN ( 'S', 'G', 'U' ) AND p.name <> 'sa'
					ELSE
					 DECLARE login_curs CURSOR FOR

					SELECT p.sid, p.name, p.type, p.is_disabled, p.default_database_name, l.hasaccess, l.denylogin FROM 
					sys.server_principals p LEFT JOIN sys.syslogins l
					ON ( l.name = p.name ) WHERE p.type IN ( 'S', 'G', 'U' ) AND p.name = @login_name 
					OPEN login_curs

					FETCH NEXT FROM login_curs INTO @SID_varbinary, @name, @type, @is_disabled, @defaultdb, @hasaccess, @denylogin

					WHILE (@@fetch_status <> -1)
					BEGIN
					 IF (@@fetch_status <> -2)
						BEGIN
						PRINT ''
						IF (@type IN ( 'G', 'U'))
							BEGIN -- NT authenticated account/group
							SET @tmpstr = 'CREATE LOGIN ' + QUOTENAME( @name ) + ' FROM WINDOWS WITH DEFAULT_DATABASE = [' + @defaultdb + ']'
							set @loginType = 'W'
					  END
					ELSE BEGIN -- SQL Server authentication
					-- obtain password and sid
					SET @PWD_varbinary = CAST( LOGINPROPERTY( @name, 'PasswordHash' ) AS varbinary (256) )
					EXEC sp_hexadecimal @PWD_varbinary, @PWD_string OUT
					EXEC sp_hexadecimal @SID_varbinary,@SID_string OUT
												   
					-- obtain password policy state
					SELECT @is_policy_checked = CASE is_policy_checked WHEN 1 THEN 'ON' WHEN 0 THEN 'OFF' ELSE NULL END FROM sys.sql_logins WHERE name = @name        SELECT @is_expiration_checked = CASE is_expiration_checked WHEN 1 THEN 'ON' WHEN 0 THEN 'OFF' ELSE NULL END FROM sys.sql_logins WHERE name = @name 
					SET @tmpstr = 'CREATE LOGIN ' + QUOTENAME( @name ) + ' WITH PASSWORD = ' + @PWD_string + ' HASHED, SID = ' + @SID_string + ', DEFAULT_DATABASE = [' + @defaultdb + ']'
					set @loginType = 'S'
					IF ( @is_policy_checked IS NOT NULL )
					 BEGIN
					SET @tmpstr = @tmpstr + ', CHECK_POLICY = ' + @is_policy_checked        END
					IF ( @is_expiration_checked IS NOT NULL )
						BEGIN
						SET @tmpstr = @tmpstr + ', CHECK_EXPIRATION = ' + @is_expiration_checked        END
						END
					IF (@denylogin = 1)
						BEGIN -- login is denied access
						SET @tmpstr = @tmpstr + '; DENY CONNECT SQL TO ' + QUOTENAME( @name )
						END
					ELSE IF (@hasaccess = 0)
						BEGIN -- login exists but does not have access
						SET @tmpstr = @tmpstr + '; REVOKE CONNECT SQL TO ' + QUOTENAME( @name )
						END
					IF (@is_disabled = 1)
						BEGIN -- login is disabled
						SET @tmpstr = @tmpstr + '; ALTER LOGIN ' + QUOTENAME( @name ) + ' DISABLE'
						END
					update #replicadbusers set adduserlogincommand = @tmpstr, SID_string = @SID_string, LoginType = @loginType where useridcounter = @useridcounter
																																																					   END
					 FETCH NEXT FROM login_curs INTO @SID_varbinary, @name, @type, @is_disabled, @defaultdb, @hasaccess, @denylogin
					END
					CLOSE login_curs
					DEALLOCATE login_curs
			
	FETCH NEXT FROM loginscursor INTO @useridcounter, @login_name
	End
CLOSE loginscursor
DEALLOCATE loginscursor



select * from #replicadbusers



drop table #replicadbs
drop table #replicadbusers

End
go

USE master
GO
IF OBJECT_ID ('usp_Compare_Login_SID') IS NOT NULL
  DROP PROCEDURE usp_Compare_Login_SID
  GO


create procedure usp_Compare_Login_SID

@login_name sysname, 
@sidstring Nvarchar (514)
as
Begin

	DECLARE @SID_varbinary varbinary (85)
	DECLARE @SID_string varchar (514) 
	select @SID_varbinary = sid from sys.syslogins where name = @login_name

	EXEC sp_hexadecimal @SID_varbinary,@SID_string OUT

	if @sidstring = @SID_string
		begin
		select 1
		end
	Else
		Begin
		select 0
		end

End
go


USE master
GO
IF OBJECT_ID ('usp_Drop_Login_Command') IS NOT NULL
  DROP PROCEDURE usp_Drop_Login_Command
  GO


create procedure usp_Drop_Login_Command

@login_name sysname

as
Begin
declare @command varchar(max)
set @command = 'Drop Login [' + @login_name + ']'
exec(@command)

End
go


IF OBJECT_ID ('usp_get_list_of_Login_Roles') IS NOT NULL
DROP PROCEDURE usp_get_list_of_Login_Roles
GO


create procedure usp_get_list_of_Login_Roles 
@loginName sysname,
@IncludeSysAdmin bit
as
Begin


If @IncludeSysAdmin = 1
	Begin

		SELECT SUSER_NAME(SR.role_principal_id) AS ServerRole
		, SUSER_NAME(SR.member_principal_id) AS PrincipalName,
		'ALTER SERVER ROLE ['+ SUSER_NAME(SR.role_principal_id) +'] ADD MEMBER [' + SUSER_NAME(SR.member_principal_id) + ']'

		FROM sys.server_role_members SR
		where SUSER_NAME(SR.member_principal_id) = @loginName
	end
Else 
	Begin
			SELECT SUSER_NAME(SR.role_principal_id) AS ServerRole
		, SUSER_NAME(SR.member_principal_id) AS PrincipalName,
		'ALTER SERVER ROLE ['+ SUSER_NAME(SR.role_principal_id) +'] ADD MEMBER [' + SUSER_NAME(SR.member_principal_id) + ']'

		FROM sys.server_role_members SR
		where SUSER_NAME(SR.member_principal_id) = @loginName
		and SUSER_NAME(SR.role_principal_id) <> 'sysadmin'

	End
End
go


































