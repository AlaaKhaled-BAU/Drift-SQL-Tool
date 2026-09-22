CREATE PROCEDURE [dbo].[OT_NestedIfBattery]
AS
BEGIN
    DECLARE @x INT = 10, @y INT = 5, @z VARCHAR(10) = 'a', @n INT = 3;

    /* Gate battery: IN, AND, <>, =, ELSE chain */
    IF @ClientActive IN (66, 99)
    BEGIN
        PRINT 'master-arm-in-66';
        IF @x = 10 AND @y <> 3
            PRINT 'runtime-and-ne';
        IF @x > 5 OR @z IN ('a', 'b')
            PRINT 'runtime-or-in';
        IF NOT (@y < 1)
            PRINT 'runtime-not-lt';
        IF @n >= 3 AND @x <= 100
            PRINT 'runtime-ge-le';
    END
    ELSE IF @ClientActive IN (50, 51)
    BEGIN
        PRINT 'master-generic-50-51';
        IF @x < @y OR @z = 'z'
            PRINT 'runtime-dead-generic-inner';
    END
    ELSE IF @ClientActive = 165
    BEGIN
        PRINT 'master-arm-165';
        IF @x > @y
            PRINT 'runtime-gt';
    END
    ELSE
    BEGIN
        PRINT 'master-else-harvest';
    END

    IF 66 = @ClientActive
    BEGIN
        PRINT 'master-rev-eq-66';
        IF @ClientActive NOT IN (33, 44)
            PRINT 'master-not-in-66';
    END

    /* Outer gate is another client; inner @ClientActive = 66 must not leak for client 66 */
    IF @ClientActive = 165
    BEGIN
        IF @ClientActive = 66
        BEGIN
            PRINT 'nested-ghost-inner-66';
        END
        PRINT 'nested-outer-165-only';
    END

    PRINT 'master-shared-tail';
END
