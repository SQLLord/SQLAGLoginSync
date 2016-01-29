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

 create PROCEDURE Usp_get_list_of_ag_logins 
 @Listenername NVARCHAR(63),
 @IncludeServerRolesAll Varchar(10)
AS
  BEGIN
		------Version 3.01
      ----Script to gather login info and prep for loading in secondary servers---------
      ----------------------------------------------------------------------------------
      -----create temp table to store login and replica info----------------------------
      ----------------------------------------------------------------------------------
      /****** Object:  Table [dbo].[testtable]    Script Date: 7/26/2012 3:46:10 PM ******/
      CREATE TABLE #replicadbs
        (
           [useridcounter]       [INT] IDENTITY(1, 1) NOT NULL,
           [agname]              [SYSNAME] NULL,
           [database_name]       [SYSNAME] NULL,
           [replica_server_name] [NVARCHAR](256) NULL,
           [role_desc]           [NVARCHAR](60) NULL,
           [connected_state]     [TINYINT] NULL
        )
      ON [PRIMARY]

      ---------load list of secondary servers and which dbs are mirroring to them using Always ON-------
      ---------------------------------------------------------------------------------------------------
      INSERT INTO #replicadbs
                  (agname,
                   database_name,
                   replica_server_name,
                   role_desc,
                   connected_state)
      SELECT d.name AS agname,
             c.database_name,
             b.replica_server_name,
             a.role_desc,
             a.connected_state
      FROM   sys.dm_hadr_availability_replica_states AS a
             JOIN sys.availability_replicas AS b
               ON a.replica_id = b.replica_id
             JOIN sys.availability_databases_cluster AS c
               ON a.group_id = c.group_id
             JOIN sys.availability_groups AS d
               ON a.group_id = d.group_id
             JOIN sys.availability_group_listeners AS e
               ON a.group_id = e.group_id
      WHERE  a.role_desc = 'Secondary'
             AND a.connected_state = 1
             AND e.dns_name = @Listenername

      -----------create table with replica and db and user info-------------
      ---------------------------------------------------------------------
      CREATE TABLE #replicadbusers
        (
           [useridcounter]       [INT] IDENTITY(1, 1) NOT NULL,
           [agname]              [SYSNAME] NULL,
           [database_name]       [SYSNAME] NULL,
           [replica_server_name] [NVARCHAR](256) NULL,
           [role_desc]           [NVARCHAR](60) NULL,
           [connected_state]     [TINYINT] NULL,
           [dbusername]          [SYSNAME] NULL,
           [loginname]           [SYSNAME] NULL,
           [adduserlogincommand] VARCHAR(max) NULL,
           [sid_string]          VARCHAR (514) NULL,
           [logintype]           CHAR(1) NULL,
		   [PWD_String]			 VARCHAR (514)
        )
      ON [PRIMARY]

      -----use cursor to list all users for each db that logins must be synced over with--------
      ------------------------------------------------------------------------------------------
      SET nocount ON;

      DECLARE @agname              [SYSNAME],
              @database_name       [SYSNAME],
              @replica_server_name [NVARCHAR](256),
              @role_desc           [NVARCHAR](60),
              @connected_state     [TINYINT],
              @selectcommand       VARCHAR(max)
      DECLARE replicadbs CURSOR FOR
        SELECT agname,
               database_name,
               replica_server_name,
               role_desc,
               connected_state
        FROM   #replicadbs

      OPEN replicadbs

      FETCH next FROM replicadbs INTO @agname, @database_name, @replica_server_name, @role_desc, @connected_state

      WHILE @@FETCH_STATUS = 0
        BEGIN
            SELECT @selectcommand =
					'insert into #replicadbusers (agname,database_name,replica_server_name,role_desc,connected_state,dbusername,loginname) select '''
                 + Rtrim(Ltrim(CONVERT(VARCHAR(4000), @agname)))
                 + ''', '''
                 + Rtrim(Ltrim(CONVERT(VARCHAR(4000), @database_name)))
                 + ''', '''
                 + Rtrim(Ltrim(CONVERT(VARCHAR(4000), @replica_server_name)))
                 + ''', '''
                 + Rtrim(Ltrim(CONVERT(VARCHAR(4000), @role_desc)))
                 + ''', '
                 + Rtrim(Ltrim(CONVERT(VARCHAR(4000), @connected_state)))
                 + ',  a.name, b.loginname from '
                 + Rtrim(Ltrim(CONVERT(VARCHAR(4000), @database_name)))
                 + '.sys.sysusers as a join sys.syslogins as b on a.sid = b.sid 
				  where b.loginname not like ''NT Authority%''
				  and b.loginname not like ''NT Service%''
				  and b.loginname <> ''sa''
				 '

				EXECUTE (@selectcommand)

    -- Get the next vendor.
			FETCH next FROM replicadbs INTO @agname, @database_name, @replica_server_name, @role_desc, @connected_state
		END

    CLOSE replicadbs;

    DEALLOCATE replicadbs;


	If @IncludeServerRolesAll = 'true'
		begin



		insert into #replicadbusers (agname,database_name,replica_server_name,role_desc,connected_state,dbusername,loginname)

		SELECT
	b.agname AS agname,
	b.database_name,
	b.replica_server_name,
	b.role_desc,
	b.connected_state,
	'ServerRole',
	SUSER_NAME(SR.member_principal_id) AS PrincipalName        
FROM
	(select
		distinct  d.name AS agname,
		'Master' as database_name,
		b.replica_server_name,
		a.role_desc,
		a.connected_state 
	from
		sys.dm_hadr_availability_replica_states AS a               ,
		sys.availability_replicas AS b                               ,
		sys.availability_databases_cluster AS c                               ,
		sys.availability_groups AS d                                ,
		sys.availability_group_listeners AS e      
	where
		a.replica_id = b.replica_id 
		and      a.group_id = c.group_id 
		and     a.group_id = d.group_id 
		and     a.group_id = e.group_id 
		and       a.role_desc = 'Secondary'        
		AND a.connected_state = 1) as b                         ,
	sys.server_role_members as SR     ,
	sys.server_principals as sp            
WHERE
	sr.member_principal_id = sp.principal_id 
	and          sp.is_fixed_role = 0    
	and sp.type in (
		'U', 'S'
	)     
	and sp.is_disabled = 0    
	and SUSER_NAME(SR.member_principal_id) not like 'nt service%'    
	and SUSER_NAME(SR.member_principal_id) <> 'sa'    
	and SUSER_NAME(SR.member_principal_id) not like '##%'    
	and SUSER_NAME(SR.member_principal_id) <> 'public'
	and SUSER_NAME(SR.member_principal_id) not in (select loginname from #replicadbusers)

		end





    ------use cursor so we can get the login script build from sp_rev_login---------------
    ---------------------------------------------------------------------------------------
    DECLARE @login_name SYSNAME
    DECLARE @name SYSNAME
    DECLARE @type VARCHAR (1)
    DECLARE @hasaccess INT
    DECLARE @denylogin INT
    DECLARE @is_disabled INT
    DECLARE @PWD_varbinary VARBINARY (256)
    DECLARE @PWD_string VARCHAR (514)
    DECLARE @SID_varbinary VARBINARY (85)
    DECLARE @SID_string VARCHAR (514)
    DECLARE @tmpstr VARCHAR (1024)
    DECLARE @is_policy_checked VARCHAR (3)
    DECLARE @is_expiration_checked VARCHAR (3)
    DECLARE @useridcounter INT
    DECLARE @loginType CHAR(1)
    DECLARE @defaultdb SYSNAME
    DECLARE loginscursor CURSOR FOR
      SELECT useridcounter,
             loginname
      FROM   #replicadbusers

    OPEN loginscursor

   FETCH next FROM loginscursor INTO @useridcounter, @login_name

    WHILE @@FETCH_STATUS = 0
      BEGIN
          IF ( @login_name IS NULL )
			begin
            DECLARE login_curs CURSOR FOR
              SELECT p.sid,
                     p.name,
                     p.type,
                     p.is_disabled,
                     p.default_database_name,
                     l.hasaccess,
                     l.denylogin
              FROM   sys.server_principals p
                     LEFT JOIN sys.syslogins l
                            ON ( l.name = p.name )
              WHERE  p.type IN ( 'S', 'G', 'U' )
                     AND p.name <> 'sa'
			End
          ELSE
			begin
            DECLARE login_curs CURSOR FOR
              SELECT p.sid,
                     p.name,
                     p.type,
                     p.is_disabled,
                     p.default_database_name,
                     l.hasaccess,
                     l.denylogin
              FROM   sys.server_principals p
                     LEFT JOIN sys.syslogins l
                            ON ( l.name = p.name )
              WHERE  p.type IN ( 'S', 'G', 'U' )
                     AND p.name = @login_name
			End
          OPEN login_curs

          FETCH next FROM login_curs INTO @SID_varbinary, @name, @type, @is_disabled, @defaultdb, @hasaccess, @denylogin

          WHILE ( @@fetch_status <> -1 )
            BEGIN
                IF ( @@fetch_status <> -2 )
                  BEGIN
                      PRINT ''
					  
                      IF ( @type IN ( 'G', 'U' ) )
                        BEGIN -- NT authenticated account/group
						
							 SET @PWD_varbinary = Cast(
                            Loginproperty(@name, 'PasswordHash')
                            AS
                            VARBINARY (256))

                            EXEC Sp_hexadecimal
                              @PWD_varbinary,
                              @PWD_string out

                            EXEC Sp_hexadecimal
                              @SID_varbinary,
                              @SID_string out

                            SET @tmpstr = 'CREATE LOGIN ' + Quotename( @name )
                                          +
                            ' FROM WINDOWS WITH DEFAULT_DATABASE = ['
                                          + @defaultdb + ']'
                            SET @loginType = 'W'

                            UPDATE #replicadbusers
                            SET    adduserlogincommand = @tmpstr,
                                   sid_string = @SID_string,
                                   logintype = @loginType,
								   PWD_String = @PWD_string
                            WHERE  useridcounter = @useridcounter
					
                            SET @SID_string = NULL
                            SET @loginType = NULL
							set @useridcounter = NULL
							set @PWD_string = NULL
                        END
                      ELSE
                        BEGIN -- SQL Server authentication
                            -- obtain password and sid
                            SET @PWD_varbinary = Cast(
                            Loginproperty(@name, 'PasswordHash')
                            AS
                            VARBINARY (256))

                            EXEC Sp_hexadecimal
                              @PWD_varbinary,
                              @PWD_string out

                            EXEC Sp_hexadecimal
                              @SID_varbinary,
                              @SID_string out

                            -- obtain password policy state
                            SELECT @is_policy_checked = CASE is_policy_checked
                                                          WHEN 1 THEN 'ON'
                                                          WHEN 0 THEN 'OFF'
                                                          ELSE NULL
                                                        END
                            FROM   sys.sql_logins
                            WHERE  name = @name

                            SELECT @is_expiration_checked = CASE
                                   is_expiration_checked
                                                              WHEN 1 THEN 'ON'
                                                              WHEN 0 THEN 'OFF'
                                                              ELSE NULL
                                                            END
                            FROM   sys.sql_logins
                            WHERE  name = @name

                            SET @tmpstr = 'CREATE LOGIN ' + Quotename( @name )
                                          + ' WITH PASSWORD = ' + @PWD_string
                                          + ' HASHED, SID = ' + @SID_string
                                          + ', DEFAULT_DATABASE = [' +
                                          @defaultdb +
                                          ']'
                            SET @loginType = 'S'

                            IF ( @is_policy_checked IS NOT NULL )
                              BEGIN
                                  SET @tmpstr = @tmpstr + ', CHECK_POLICY = '
                                                + @is_policy_checked
                              END

                            IF ( @is_expiration_checked IS NOT NULL )
                              BEGIN
                                  SET @tmpstr =
                                  @tmpstr + ', CHECK_EXPIRATION = '
                                  + @is_expiration_checked
                              END
                        END

                      IF ( @denylogin = 1 )
                        BEGIN -- login is denied access
                            SET @tmpstr = @tmpstr + '; DENY CONNECT SQL TO '
                                          + Quotename( @name )
                        END
                      ELSE IF ( @hasaccess = 0 )
                        BEGIN -- login exists but does not have access
                            SET @tmpstr = @tmpstr + '; REVOKE CONNECT SQL TO '
                                          + Quotename( @name )
                        END

                      IF ( @is_disabled = 1 )
                        BEGIN -- login is disabled
                            SET @tmpstr = @tmpstr + '; ALTER LOGIN ' + Quotename
                                          (
                                          @name )
                                          + ' DISABLE'
                        END

                      UPDATE #replicadbusers
                      SET    adduserlogincommand = @tmpstr,
                             sid_string = @SID_string,
                             logintype = @loginType,
							 PWD_String = @PWD_string
                      WHERE  useridcounter = @useridcounter
	
					  set @useridcounter = NULL
                      SET @SID_string = NULL
                      SET @loginType = NULL
					  set @PWD_string = NULL
                  END

                FETCH next FROM login_curs INTO @SID_varbinary, @name, @type,
                @is_disabled
                ,
                @defaultdb, @hasaccess, @denylogin
            END

          CLOSE login_curs

          DEALLOCATE login_curs

          FETCH next FROM loginscursor INTO @useridcounter, @login_name
      END

    CLOSE loginscursor

    DEALLOCATE loginscursor

    SELECT *
    FROM   #replicadbusers --where [SID_string] is not null
    DROP TABLE #replicadbs

    DROP TABLE #replicadbusers
END

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
	-----version 3.01
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
IF OBJECT_ID ('usp_Compare_Login_PWD') IS NOT NULL
  DROP PROCEDURE usp_Compare_Login_PWD
  GO


create procedure usp_Compare_Login_PWD

@login_name sysname, 
@PWDstring Nvarchar (514)
as
Begin
	----version 3.01
	DECLARE @PWD_varbinary VARBINARY (256)
	DECLARE @PWD_string varchar (514) 
	

	SET @PWD_varbinary = Cast(
                            Loginproperty(@login_name, 'PasswordHash')
                            AS
                            VARBINARY (256))


	EXEC sp_hexadecimal @PWD_varbinary,@PWD_string OUT

	if @PWDstring = @PWD_string
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
---version 3.01
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
---version 3.01

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


































